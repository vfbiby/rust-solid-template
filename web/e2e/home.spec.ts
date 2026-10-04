import { expect, test } from "@playwright/test";

test.beforeAll(async ({ request }) => {
  // baseURL 未解析到时相对路径会直接抛错，同样落进可见 skip。
  let reachable = false;
  try {
    reachable = (await request.get("/health")).ok();
  } catch {
    reachable = false;
  }
  test.skip(!reachable, `dev 栈未启动：./dev.sh start（baseURL=${test.info().project.use.baseURL ?? "未解析到"}）`);
});

test("首页加载出 items 列表骨架", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "items" })).toBeVisible();
  await expect(page.getByRole("button", { name: "添加" })).toBeVisible();
});

test("通过 UI 添加一项并出现在列表（走 vite proxy → 后端 → 真库）", async ({ page }) => {
  const name = `e2e-${Date.now()}`;
  await page.goto("/");
  await page.getByPlaceholder("名称").fill(name);
  await page.getByRole("button", { name: "添加" }).click();
  await expect(page.getByRole("listitem").filter({ hasText: name })).toBeVisible();
});
