use axum::extract::State;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

#[derive(Serialize, sqlx::FromRow)]
pub struct Item {
    id: i64,
    name: String,
    created_at: DateTime<Utc>,
}

#[derive(Deserialize)]
pub struct NewItem {
    name: String,
}

pub async fn list(State(pool): State<PgPool>) -> Json<Vec<Item>> {
    let items = sqlx::query_as::<_, Item>("select id, name, created_at from items order by id")
        .fetch_all(&pool)
        .await
        .expect("查询 items");
    Json(items)
}

pub async fn create(State(pool): State<PgPool>, Json(input): Json<NewItem>) -> Json<Item> {
    let item = sqlx::query_as::<_, Item>(
        "insert into items (name) values ($1) returning id, name, created_at",
    )
    .bind(&input.name)
    .fetch_one(&pool)
    .await
    .expect("插入 item");
    Json(item)
}
