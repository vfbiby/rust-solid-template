import { createResource, createSignal, For, Show } from "solid-js";
import { apiGet, apiPost } from "./api";

interface Item {
  id: number;
  name: string;
}

export default function App() {
  const [items, { refetch }] = createResource<Item[]>(() => apiGet("/api/items"));
  const [name, setName] = createSignal("");
  const [error, setError] = createSignal("");

  const add = async () => {
    const value = name().trim();
    if (!value) return;
    try {
      await apiPost("/api/items", { name: value });
      setName("");
      setError("");
      await refetch();
    } catch (e) {
      setError(String(e));
    }
  };

  return (
    <main>
      <h1>items</h1>
      <div>
        <input
          value={name()}
          onInput={(e) => setName(e.currentTarget.value)}
          placeholder="名称"
        />
        <button type="button" onClick={add}>
          添加
        </button>
      </div>
      <Show when={error()}>
        <p role="alert">{error()}</p>
      </Show>
      <ul>
        <For each={items()}>{(item) => <li>{item.name}</li>}</For>
      </ul>
    </main>
  );
}
