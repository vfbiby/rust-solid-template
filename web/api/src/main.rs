#[tokio::main]
async fn main() {
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let db_url = std::env::var("DATABASE_URL").expect("DATABASE_URL 未设置");

    let pool = server::store::pool(&db_url).await;
    server::store::migrate(&pool).await;

    let listener = tokio::net::TcpListener::bind(("127.0.0.1", port))
        .await
        .unwrap_or_else(|e| panic!("绑 127.0.0.1:{port} 失败：{e}"));
    axum::serve(listener, server::router(pool))
        .await
        .expect("serve");
}
