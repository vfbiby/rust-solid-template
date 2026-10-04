// vitest 全局：stub 掉 fetch，默认空响应，单个测试自行覆写。
import { vi } from "vitest";

const fetchMock = vi.fn(async () => new Response("[]", { status: 200 }));

vi.stubGlobal("fetch", fetchMock);

export { fetchMock };
