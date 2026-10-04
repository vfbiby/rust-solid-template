pub mod items;
pub mod store;

use axum::routing::get;
use axum::Router;
use sqlx::PgPool;

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/api/items", get(items::list).post(items::create))
        .with_state(pool)
}

async fn health() -> &'static str {
    "ok"
}
