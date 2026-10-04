mod common;

use axum::body::Body;
use axum::http::Request;
use common::test_router;
use http_body_util::BodyExt;
use serde_json::json;
use tower::ServiceExt;

async fn json_body(body: Body) -> serde_json::Value {
    let bytes = body.collect().await.expect("read body").to_bytes();
    serde_json::from_slice(&bytes).expect("json body")
}

#[tokio::test]
async fn health_is_ok() {
    let (app, _db) = test_router().await;
    let res = app
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let bytes = res
        .into_body()
        .collect()
        .await
        .expect("read body")
        .to_bytes();
    assert_eq!(bytes.as_ref(), b"ok");
}

#[tokio::test]
async fn create_then_list_items() {
    let (app, _db) = test_router().await;

    let res = app
        .clone()
        .oneshot(
            Request::post("/api/items")
                .header("content-type", "application/json")
                .body(Body::from(json!({"name": "第一件"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let created = json_body(res.into_body()).await;
    assert_eq!(created["name"], json!("第一件"));
    assert!(created["id"].is_i64());

    let res = app
        .oneshot(Request::get("/api/items").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(res.status(), 200);
    let items = json_body(res.into_body()).await;
    assert_eq!(items.as_array().map(Vec::len), Some(1));
    assert_eq!(items[0]["name"], json!("第一件"));
}
