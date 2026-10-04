import { render } from "@solidjs/testing-library";
import { expect, test, vi } from "vitest";
import App from "./App";
import { fetchMock } from "../tests/setup";

test("拉到 items 后渲染成列表", async () => {
  fetchMock.mockImplementation(
    async () =>
      new Response(JSON.stringify([{ id: 1, name: "示例物" }]), { status: 200 }),
  );

  const { findByText } = render(() => <App />);
  expect(await findByText("示例物")).toBeTruthy();
  expect(vi.mocked(fetchMock)).toHaveBeenCalledWith(
    "/api/items",
    expect.objectContaining({ headers: expect.anything() }),
  );
});
