//! 测试基座：一台本地 Postgres，迁移一次进模板库，每个测试克隆一个库。
//!
//! 连接串取 `RSTS_TEST_PG_URL`（APP 大写前缀），默认本机 5433。库名带 pid 与
//! 进程启动毫秒，运行期只建不删：`DROP DATABASE` 会触发强制检查点，让所有测试
//! 一起等。进程已退出的库由 `scripts/cargo-test.sh` 在跑测试前后统一清掉。
//!
//! 改 APP 名时这里的 `const APP` 也要改（README「起名」一节）。
#![allow(dead_code)]

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::LazyLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use axum::Router;
use server::store::MIGRATOR;
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use tokio::sync::OnceCell;

const APP: &str = "rsts";
const DEFAULT_PG_URL: &str = "postgres://postgres@127.0.0.1:5433/postgres";
const LEFTOVER_WARN_THRESHOLD: i64 = 1000;

static SETUP: OnceCell<()> = OnceCell::const_new();
static COUNTER: AtomicUsize = AtomicUsize::new(0);
static STARTED_MS: LazyLock<u128> = LazyLock::new(|| {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock after epoch")
        .as_millis()
});

/// 一个测试独占的库，外加连它的池。
pub struct TestDb {
    pool: PgPool,
    url: String,
}

impl TestDb {
    pub async fn new() -> TestDb {
        SETUP.get_or_init(setup).await;
        let name = unique_name("test");
        let admin = admin_pool().await;
        let template = template_name();
        exec(
            &admin,
            &format!("create database {name} template {template}"),
        )
        .await;
        admin.close().await;

        let url = with_database(&pg_url(), &name);
        let pool = PgPoolOptions::new()
            .max_connections(5)
            .acquire_timeout(Duration::from_secs(20))
            .connect(&url)
            .await
            .expect("connect test database");
        TestDb { pool, url }
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    pub fn url(&self) -> &str {
        &self.url
    }
}

/// 被测件一步到位：克隆一个新库 + 挂上完整 router。
pub async fn test_router() -> (Router, TestDb) {
    let db = TestDb::new().await;
    let app = server::router(db.pool.clone());
    (app, db)
}

fn pg_url() -> String {
    std::env::var(format!("{}_TEST_PG_URL", APP.to_uppercase()))
        .ok()
        .unwrap_or_else(|| DEFAULT_PG_URL.to_owned())
}

fn with_database(base: &str, database: &str) -> String {
    let base = base.split('?').next().unwrap_or(base);
    let cut = base.rfind('/').map_or(base.len(), |i| i + 1);
    format!("{}{database}", &base[..cut])
}

fn process_tag() -> String {
    format!("{}_{}", std::process::id(), *STARTED_MS)
}

fn unique_name(kind: &str) -> String {
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    format!("{APP}_{kind}_{}_{n}", process_tag())
}

fn template_name() -> String {
    format!("{APP}_template_{}", process_tag())
}

async fn admin_pool() -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .acquire_timeout(Duration::from_secs(20))
        .connect(&pg_url())
        .await
        .unwrap_or_else(|error| {
            panic!(
                "连不上测试用 Postgres（{}）：{error}\n\
                 本机装一个：brew install postgresql@16，角色需 CREATEDB；\
                 或用 {}_TEST_PG_URL 指到别的实例。",
                pg_url(),
                APP.to_uppercase()
            )
        })
}

async fn setup() {
    let admin = admin_pool().await;
    warn_on_leftover_databases(&admin).await;

    let template = template_name();
    exec(&admin, &format!("create database {template}")).await;
    admin.close().await;

    let pool = PgPoolOptions::new()
        .max_connections(4)
        .connect(&with_database(&pg_url(), &template))
        .await
        .expect("connect template database");
    MIGRATOR
        .run(&pool)
        .await
        .expect("migrate template database");
    // 模板库被克隆时不能有连接挂着。
    pool.close().await;
}

async fn warn_on_leftover_databases(admin: &PgPool) {
    let count: i64 = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "select count(*) from pg_database where datname like '{APP}\\_test\\_%' or datname like '{APP}\\_template\\_%'"
    )))
    .fetch_one(admin)
    .await
    .unwrap_or(0);
    if count > LEFTOVER_WARN_THRESHOLD {
        eprintln!("请运行 scripts/cargo-test.sh 清理遗留测试库");
    }
}

async fn exec(pool: &PgPool, statement: &str) {
    sqlx::raw_sql(sqlx::AssertSqlSafe(statement.to_owned()))
        .execute(pool)
        .await
        .unwrap_or_else(|error| panic!("{statement}: {error}"));
}
