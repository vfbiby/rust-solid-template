use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use std::time::Duration;

pub static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("./migrations");

pub async fn pool(url: &str) -> PgPool {
    PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(20))
        .connect(url)
        .await
        .unwrap_or_else(|e| panic!("连不上数据库（{url}）：{e}"))
}

pub async fn migrate(pool: &PgPool) {
    MIGRATOR.run(pool).await.expect("迁移失败");
}
