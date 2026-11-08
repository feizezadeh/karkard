use thiserror::Error;

#[derive(Error, Debug)]
pub enum KarkardError {
    #[error("خطای پایگاه داده: {0}")]
    Database(#[from] rusqlite::Error),

    #[error("خطای دامنه [{code}]: {message}")]
    Domain {
        code: &'static str,
        message: String,
    },

    #[error("خطای فایل اکسل: {0}")]
    Excel(String),

    #[error("خطای اعتبارسنجی: {0}")]
    Validation(String),

    #[error("مورد یافت نشد: {0}")]
    NotFound(String),

    #[error("پروژه قفل است: {0}")]
    Locked(String),

    #[error("خطای ورودی/خروجی: {0}")]
    Io(#[from] std::io::Error),

    #[error("خطای پشتیبان‌گیری: {0}")]
    Backup(String),
}

pub type Result<T> = std::result::Result<T, KarkardError>;
