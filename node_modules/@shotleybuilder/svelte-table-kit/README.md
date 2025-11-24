# 🎯 Svelte Table Kit

**A comprehensive, AI-configurable data table component for Svelte and SvelteKit, built on TanStack Table v8.**

[![npm version](https://img.shields.io/npm/v/@sertantai/svelte-table-kit.svg)](https://www.npmjs.com/package/@sertantai/svelte-table-kit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Svelte Table Kit brings Airtable-like functionality to your Svelte applications with a headless, fully customizable table component. Perfect for dashboards, data grids, and complex data visualization needs.

---

## ✨ Features

**Core Table Features:**
- 🎯 Column visibility picker with show/hide controls
- 📏 Column resizing with drag handles
- 🔄 Column reordering via native HTML5 drag & drop
- 🔍 **Advanced filtering** - 12 operators with AND/OR logic
- 📊 **Multi-level grouping** - Up to 3 nested levels (like Airtable)
- ⬆️ Multi-column sorting with visual indicators
- 📄 Pagination with customizable page sizes
- 💾 LocalStorage persistence for all user preferences

**Advanced Filtering:**
- 12 filter operators: equals, contains, starts with, greater than, etc.
- AND/OR logic between conditions
- Collapsible FilterBar UI (space-efficient)
- Active filter count badge
- Real-time filtering as you type

**Grouping & Hierarchy:**
- Group by up to 3 columns simultaneously
- Expand/collapse groups with chevron buttons
- Visual indentation based on nesting level
- Item count per group
- Collapsible GroupBar UI

**Developer Experience:**
- 🎨 Headless design - style it your way
- 📦 Built on TanStack Table v8 (battle-tested, powerful)
- 🔒 Full TypeScript support
- 🎛️ Feature flags for granular control
- 🚀 Zero external dependencies (except TanStack Table)
- ♿ Accessible and keyboard-friendly

**AI-Ready:**
- 🤖 JSON-schema driven configuration
- 🧠 AI agents can generate table configs from natural language
- 📋 Preset configurations for common use cases
- 🔧 Programmatic table setup and state management

📅 **[View Development Roadmap](./ROADMAP.md)** - See what's coming next!

---

## 📦 Installation

```bash
npm install @sertantai/svelte-table-kit
```

Or using pnpm:

```bash
pnpm add @sertantai/svelte-table-kit
```

---

## 🚀 Quick Start

```svelte
<script>
  import { TableKit } from '@sertantai/svelte-table-kit';

  const data = [
    { id: 1, name: 'Alice', role: 'Developer', age: 28 },
    { id: 2, name: 'Bob', role: 'Designer', age: 32 },
    { id: 3, name: 'Charlie', role: 'Manager', age: 45 }
  ];

  const columns = [
    { accessorKey: 'id', header: 'ID' },
    { accessorKey: 'name', header: 'Name' },
    { accessorKey: 'role', header: 'Role' },
    { accessorKey: 'age', header: 'Age' }
  ];
</script>

<TableKit {data} {columns} storageKey="my-table" />
```

---

## 📚 Documentation

### Basic Usage

The simplest way to use TableKit:

```svelte
<TableKit {data} {columns} />
```

### With Configuration

Use AI-generated or predefined configurations:

```svelte
<script>
  import { TableKit, presets } from '@sertantai/svelte-table-kit';

  const config = presets.dashboard; // or generate with AI
</script>

<TableKit
  {data}
  {columns}
  {config}
  features={{
    columnVisibility: true,
    filtering: true,
    sorting: true,
    pagination: true
  }}
/>
```

### Feature Flags

Control which features are enabled:

```svelte
<TableKit
  {data}
  {columns}
  features={{
    columnVisibility: true,
    columnResizing: true,
    columnReordering: true,
    filtering: true,
    sorting: true,
    pagination: true,
    rowSelection: false,
    grouping: false
  }}
/>
```

### Event Handlers

Listen to table events:

```svelte
<TableKit
  {data}
  {columns}
  onRowClick={(row) => console.log('Clicked:', row)}
  onRowSelect={(rows) => console.log('Selected:', rows)}
  onStateChange={(state) => console.log('State:', state)}
/>
```

---

## 🎨 Styling

TableKit is headless by default. You can:

1. **Use default styles** (coming soon)
2. **Customize with classNames**:

```svelte
<TableKit
  {data}
  {columns}
  classNames={{
    container: 'my-container',
    table: 'my-table',
    th: 'my-header'
  }}
/>
```

3. **Theme support**:

```svelte
<TableKit {data} {columns} theme="dark" />
```

---

## 🧬 API Reference

### Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `data` | `T[]` | `[]` | Table data array |
| `columns` | `ColumnDef<T>[]` | `[]` | Column definitions |
| `config` | `TableConfig` | `undefined` | AI-generated or preset config |
| `features` | `TableFeatures` | All enabled | Feature flags |
| `storageKey` | `string` | `undefined` | LocalStorage key for persistence |
| `persistState` | `boolean` | `true` | Enable state persistence |
| `theme` | `'light' \| 'dark' \| 'auto'` | `'light'` | Theme mode |
| `onRowClick` | `(row: T) => void` | `undefined` | Row click handler |
| `onRowSelect` | `(rows: T[]) => void` | `undefined` | Row selection handler |
| `onStateChange` | `(state: TableState) => void` | `undefined` | State change handler |

---

## 🎯 Use Cases

- Enterprise dashboards and data visualization
- Admin panels and back-office tools
- Analytics interfaces with complex filtering
- Data exploration and reporting tools
- Any application needing Airtable/Baserow-like table UX

---

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) (coming soon).

---

## 📄 License

MIT © [Sertantai](https://github.com/shotleybuilder)

---

## 🔗 Links

- [GitHub Repository](https://github.com/shotleybuilder/svelte-table-kit)
- [npm Package](https://www.npmjs.com/package/@sertantai/svelte-table-kit)
- [Issue Tracker](https://github.com/shotleybuilder/svelte-table-kit/issues)

---

## 🙏 Acknowledgments

Built with:
- [TanStack Table](https://tanstack.com/table) - Headless table library
- [Svelte](https://svelte.dev) - Cybernetically enhanced web apps
- [SvelteKit](https://kit.svelte.dev) - The fastest way to build Svelte apps
