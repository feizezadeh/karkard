use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::error::{KarkardError, Result};
use crate::schema::SCHEMA_VERSION;

const SQLITE_HEADER: &[u8; 16] = b"SQLite format 3\0";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackupMetadata {
    pub file_path: String,
    pub file_name: String,
    pub file_size: u64,
    pub created_at: String,
    pub sha256: String,
}

pub struct BackupService;

impl BackupService {
    /// Computes the SHA-256 hash of a file on disk.
    pub fn compute_file_sha256<P: AsRef<Path>>(path: P) -> Result<String> {
        let mut file = File::open(path)?;
        let mut hasher = Sha256::new();
        let mut buffer = [0u8; 8192];
        loop {
            let n = file.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            hasher.update(&buffer[..n]);
        }
        let hash = hasher.finalize();
        Ok(hash.iter().map(|b| format!("{:02x}", b)).collect())
    }

    /// Creates an atomic safe backup of the active database using VACUUM INTO.
    pub fn create_backup(conn: &Connection, target_dir: &Path) -> Result<BackupMetadata> {
        fs::create_dir_all(target_dir)?;

        let timestamp = chrono::Local::now().format("%Y%m%d_%H%M%S");
        let file_name = format!("karkard_backup_{}.db", timestamp);
        let target_path = target_dir.join(&file_name);

        let target_str = target_path
            .to_str()
            .ok_or_else(|| KarkardError::Backup("مسیر نامعتبر برای ذخیره فایل پشتیبان".into()))?;

        // VACUUM INTO creates a consistent, defragmented point-in-time snapshot
        conn.execute("VACUUM INTO ?1", [target_str])?;

        let meta = fs::metadata(&target_path)?;
        let sha256 = Self::compute_file_sha256(&target_path)?;

        Ok(BackupMetadata {
            file_path: target_str.to_string(),
            file_name,
            file_size: meta.len(),
            created_at: chrono::Local::now().to_rfc3339(),
            sha256,
        })
    }

    /// Lists all backup files in the target directory ordered by newest first.
    pub fn list_backups(target_dir: &Path) -> Result<Vec<BackupMetadata>> {
        if !target_dir.exists() {
            return Ok(Vec::new());
        }
        let mut backups = Vec::new();
        for entry in fs::read_dir(target_dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_file() && path.extension().and_then(|s| s.to_str()) == Some("db") {
                if let Ok(meta) = entry.metadata() {
                    let file_name = path.file_name().unwrap_or_default().to_string_lossy().to_string();
                    let sha256 = Self::compute_file_sha256(&path).unwrap_or_default();
                    let created_at = meta.modified()
                        .map(|t| chrono::DateTime::<chrono::Local>::from(t).to_rfc3339())
                        .unwrap_or_else(|_| chrono::Local::now().to_rfc3339());
                    backups.push(BackupMetadata {
                        file_path: path.to_string_lossy().to_string(),
                        file_name,
                        file_size: meta.len(),
                        created_at,
                        sha256,
                    });
                }
            }
        }
        backups.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        Ok(backups)
    }

    /// Verifies that a file is a valid SQLite 3 database and checks required schema version.
    pub fn verify_backup_file<P: AsRef<Path>>(path: P) -> Result<()> {
        let mut file = File::open(&path)?;
        let mut header = [0u8; 16];
        file.read_exact(&mut header).map_err(|_| {
            KarkardError::Backup("فایل انتخاب‌شده خیلی کوتاه است یا هدر نامعتبر دارد".into())
        })?;

        if &header != SQLITE_HEADER {
            return Err(KarkardError::Backup("فایل انتخاب‌شده پایگاه‌داده SQLite معتبر نیست".into()));
        }

        // Open read-only connection to check schema_version
        let conn = Connection::open_with_flags(&path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        let version_str: String = conn
            .query_row(
                "SELECT value FROM app_settings WHERE key = 'schema_version'",
                [],
                |row| row.get(0),
            )
            .map_err(|_| KarkardError::Backup("پایگاه داده فاقد جدول app_settings یا نسخه اسکیمای معتبر است".into()))?;

        let ver: i32 = version_str.parse().map_err(|_| {
            KarkardError::Backup("نسخه اسکیما در فایل پشتیبان نامعتبر است".into())
        })?;

        if ver < SCHEMA_VERSION {
            return Err(KarkardError::Backup(format!(
                "نسخه فایل پشتیبان ({}) قدیمی‌تر از نسخه برنامه ({}) است",
                ver, SCHEMA_VERSION
            )));
        }

        Ok(())
    }

    /// Restores a backup file to `active_db_path` safely with an automatic pre-flight fallback.
    pub fn restore_backup<P: AsRef<Path>>(backup_path: P, active_db_path: P) -> Result<()> {
        Self::verify_backup_file(&backup_path)?;

        let active_path = active_db_path.as_ref();
        let parent = active_path.parent().unwrap_or_else(|| Path::new("."));

        // Pre-flight backup of the existing database if it exists
        if active_path.exists() {
            let pre_flight_name = format!("karkard_pre_restore_{}.db", chrono::Local::now().format("%Y%m%d_%H%M%S"));
            let pre_flight_path = parent.join(pre_flight_name);
            fs::copy(active_path, &pre_flight_path)?;
        }

        // Copy backup to active path
        fs::copy(backup_path, active_path)?;

        // Remove any stale WAL / SHM files
        let wal_path = parent.join(format!("{}-wal", active_path.file_name().unwrap().to_str().unwrap()));
        let shm_path = parent.join(format!("{}-shm", active_path.file_name().unwrap().to_str().unwrap()));
        let _ = fs::remove_file(wal_path);
        let _ = fs::remove_file(shm_path);

        Ok(())
    }
}
