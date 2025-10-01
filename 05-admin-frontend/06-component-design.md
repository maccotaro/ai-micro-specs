# 06-component-design.md - コンポーネント設計

## 概要

Admin Frontendは、shadcn/uiをベースとした再利用可能なコンポーネントライブラリと、ドメイン固有のカスタムコンポーネントで構成されています。コンポーネント設計は、Atomic Design原則に基づき、小さな基本コンポーネントから複雑な画面コンポーネントへと階層的に構築されています。

## コンポーネント階層

```
┌─────────────────────────────────────────────┐
│ Pages (画面)                                │
│ - index.tsx, dashboard/index.tsx           │
│ - documents/index.tsx, ocr/[id].tsx        │
└──────────────┬──────────────────────────────┘
               │
┌──────────────┴──────────────────────────────┐
│ Templates (テンプレート)                    │
│ - Layout                                    │
└──────────────┬──────────────────────────────┘
               │
┌──────────────┴──────────────────────────────┐
│ Organisms (複合コンポーネント)              │
│ - DocumentPreviewCanvas                     │
│ - DocumentStructureSidebar                  │
│ - OCRTextEditor                             │
│ - UserTable, StatCard                       │
└──────────────┬──────────────────────────────┘
               │
┌──────────────┴──────────────────────────────┐
│ Molecules (分子コンポーネント)              │
│ - DocumentCard, ChartContainer              │
└──────────────┬──────────────────────────────┘
               │
┌──────────────┴──────────────────────────────┐
│ Atoms (基本コンポーネント - shadcn/ui)      │
│ - Button, Input, Select, Dialog             │
│ - Card, Table, Badge, Alert                 │
└─────────────────────────────────────────────┘
```

## shadcn/ui基本コンポーネント

### Button

**ファイル:** `/src/components/ui/button.tsx`

```typescript
import * as React from "react"
import { Slot } from "@radix-ui/react-slot"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"

const buttonVariants = cva(
  "inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground hover:bg-primary/90",
        destructive: "bg-destructive text-destructive-foreground hover:bg-destructive/90",
        outline: "border border-input bg-background hover:bg-accent",
        secondary: "bg-secondary text-secondary-foreground hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline",
      },
      size: {
        default: "h-10 px-4 py-2",
        sm: "h-9 rounded-md px-3",
        lg: "h-11 rounded-md px-8",
        icon: "h-10 w-10",
      },
    },
    defaultVariants: {
      variant: "default",
      size: "default",
    },
  }
)

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button"
    return (
      <Comp
        className={cn(buttonVariants({ variant, size, className }))}
        ref={ref}
        {...props}
      />
    )
  }
)

export { Button, buttonVariants }
```

**使用例:**

```typescript
// Primary button
<Button>保存</Button>

// Destructive button
<Button variant="destructive">削除</Button>

// Outline button
<Button variant="outline">キャンセル</Button>

// Icon button
<Button variant="ghost" size="icon">
  <TrashIcon className="h-4 w-4" />
</Button>

// Disabled button
<Button disabled>処理中...</Button>
```

### Dialog / AlertDialog

**ファイル:** `/src/components/ui/alert-dialog.tsx`

```typescript
import * as React from "react"
import * as AlertDialogPrimitive from "@radix-ui/react-alert-dialog"
import { cn } from "@/lib/utils"

const AlertDialog = AlertDialogPrimitive.Root
const AlertDialogTrigger = AlertDialogPrimitive.Trigger

const AlertDialogContent = React.forwardRef<
  React.ElementRef<typeof AlertDialogPrimitive.Content>,
  React.ComponentPropsWithoutRef<typeof AlertDialogPrimitive.Content>
>(({ className, ...props }, ref) => (
  <AlertDialogPrimitive.Portal>
    <AlertDialogPrimitive.Overlay className="fixed inset-0 z-50 bg-background/80 backdrop-blur-sm" />
    <AlertDialogPrimitive.Content
      ref={ref}
      className={cn(
        "fixed left-[50%] top-[50%] z-50 grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 border bg-background p-6 shadow-lg sm:rounded-lg",
        className
      )}
      {...props}
    />
  </AlertDialogPrimitive.Portal>
))

export {
  AlertDialog,
  AlertDialogTrigger,
  AlertDialogContent,
  AlertDialogHeader,
  AlertDialogFooter,
  AlertDialogTitle,
  AlertDialogDescription,
  AlertDialogAction,
  AlertDialogCancel,
}
```

**使用例:**

```typescript
<AlertDialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>矩形要素の削除</AlertDialogTitle>
      <AlertDialogDescription>
        この操作は取り消すことができません。本当に削除しますか?
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel>キャンセル</AlertDialogCancel>
      <AlertDialogAction onClick={handleDelete}>
        削除する
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

### Table

**ファイル:** `/src/components/ui/table.tsx`

```typescript
const Table = React.forwardRef<
  HTMLTableElement,
  React.HTMLAttributes<HTMLTableElement>
>(({ className, ...props }, ref) => (
  <div className="w-full overflow-auto">
    <table
      ref={ref}
      className={cn("w-full caption-bottom text-sm", className)}
      {...props}
    />
  </div>
))

const TableHeader = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
  <thead ref={ref} className={cn("[&_tr]:border-b", className)} {...props} />
))

const TableBody = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
  <tbody
    ref={ref}
    className={cn("[&_tr:last-child]:border-0", className)}
    {...props}
  />
))

const TableRow = React.forwardRef<
  HTMLTableRowElement,
  React.HTMLAttributes<HTMLTableRowElement>
>(({ className, ...props }, ref) => (
  <tr
    ref={ref}
    className={cn(
      "border-b transition-colors hover:bg-muted/50",
      className
    )}
    {...props}
  />
))

const TableCell = React.forwardRef<
  HTMLTableCellElement,
  React.TdHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
  <td
    ref={ref}
    className={cn("p-4 align-middle", className)}
    {...props}
  />
))

export { Table, TableHeader, TableBody, TableRow, TableHead, TableCell }
```

## レイアウトコンポーネント

### Layout

**目的:** アプリ全体の共通レイアウト（ヘッダー、サイドバー、コンテンツエリア）

**ファイル:** `/src/components/Layout/Layout.tsx`

**構造:**

```
┌────────────────────────────────────────┐
│ Header (固定)                          │
├────────┬───────────────────────────────┤
│        │                               │
│ Side   │ Content Area                  │
│ bar    │ (children)                    │
│        │                               │
│        │                               │
└────────┴───────────────────────────────┘
```

**Props:**

```typescript
interface LayoutProps {
  children: React.ReactNode;
  maxWidth?: string; // 'max-w-7xl', 'max-w-full', または undefined
}
```

**特徴:**

- サイドバーの折りたたみ状態をsessionStorageで永続化
- 認証状態による条件付きレンダリング
- ログアウト中のローディング表示
- レスポンシブ対応（モバイルでオーバーレイサイドバー）

### Sidebar

**目的:** ナビゲーションメニュー

**ファイル:** `/src/components/Layout/Sidebar.tsx`

```typescript
const navItems = [
  { name: 'ダッシュボード', href: '/dashboard', icon: ChartBarIcon },
  { name: 'ユーザー管理', href: '/users', icon: UsersIcon },
  { name: 'ドキュメント', href: '/documents', icon: DocumentTextIcon },
  { name: 'ナレッジベース', href: '/knowledgebase', icon: BookOpenIcon },
  { name: 'プロンプト', href: '/prompt-templates', icon: SparklesIcon },
  { name: 'ログ', href: '/logs', icon: ClipboardDocumentListIcon },
  { name: 'レポート', href: '/reports', icon: ChartPieIcon },
  { name: '設定', href: '/settings', icon: CogIcon },
];

interface SidebarProps {
  collapsed?: boolean;
}

export function Sidebar({ collapsed = false }: SidebarProps) {
  const router = useRouter();

  return (
    <div className={cn(
      "flex flex-col h-full bg-gray-900 text-white transition-all",
      collapsed ? "w-16" : "w-64"
    )}>
      {/* ロゴ */}
      <div className="flex items-center justify-center h-16 border-b border-gray-800">
        {collapsed ? (
          <span className="text-xl font-bold">A</span>
        ) : (
          <span className="text-xl font-bold">Admin Portal</span>
        )}
      </div>

      {/* ナビゲーションアイテム */}
      <nav className="flex-1 px-2 py-4 space-y-1">
        {navItems.map((item) => {
          const isActive = router.pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center px-3 py-2 rounded-md transition-colors",
                isActive
                  ? "bg-gray-800 text-white"
                  : "text-gray-300 hover:bg-gray-800 hover:text-white"
              )}
            >
              <item.icon className="w-5 h-5" />
              {!collapsed && (
                <span className="ml-3">{item.name}</span>
              )}
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
```

### Header

**目的:** ユーザー情報表示とアクションメニュー

**ファイル:** `/src/components/Layout/Header.tsx**

```typescript
interface HeaderProps {
  onToggleSidebar: () => void;
}

export function Header({ onToggleSidebar }: HeaderProps) {
  const { user, logout } = useAuth();
  const [showUserMenu, setShowUserMenu] = useState(false);

  return (
    <header className="bg-white border-b border-gray-200">
      <div className="flex items-center justify-between px-4 py-3">
        {/* ハンバーガーメニュー（モバイル） */}
        <button
          onClick={onToggleSidebar}
          className="p-2 rounded-md md:hidden"
        >
          <Bars3Icon className="w-6 h-6" />
        </button>

        {/* 検索バー（将来実装） */}
        <div className="flex-1 max-w-lg mx-4">
          {/* Search input */}
        </div>

        {/* ユーザーメニュー */}
        <div className="relative">
          <button
            onClick={() => setShowUserMenu(!showUserMenu)}
            className="flex items-center space-x-2"
          >
            <span className="text-sm font-medium">{user?.email}</span>
            <UserCircleIcon className="w-8 h-8 text-gray-400" />
          </button>

          {showUserMenu && (
            <div className="absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg">
              <div className="py-1">
                <a
                  href="/profile"
                  className="block px-4 py-2 text-sm hover:bg-gray-100"
                >
                  プロフィール
                </a>
                <button
                  onClick={logout}
                  className="block w-full text-left px-4 py-2 text-sm hover:bg-gray-100"
                >
                  ログアウト
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
```

## ダッシュボードコンポーネント

### StatCard

**目的:** 統計情報の表示カード

**ファイル:** `/src/components/Charts/StatCard.tsx`

```typescript
interface StatCardProps {
  title: string;
  value: string | number;
  icon: React.ComponentType<{ className?: string }>;
  description?: string;
  trend?: {
    value: number;
    isPositive: boolean;
  };
  color?: 'blue' | 'green' | 'yellow' | 'red';
}

export function StatCard({
  title,
  value,
  icon: Icon,
  description,
  trend,
  color = 'blue',
}: StatCardProps) {
  const colorClasses = {
    blue: 'bg-blue-500',
    green: 'bg-green-500',
    yellow: 'bg-yellow-500',
    red: 'bg-red-500',
  };

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between">
        <div className="flex-1">
          <p className="text-sm font-medium text-gray-600">{title}</p>
          <p className="mt-2 text-3xl font-semibold text-gray-900">{value}</p>
          {description && (
            <p className="mt-1 text-sm text-gray-500">{description}</p>
          )}
          {trend && (
            <div className="mt-2 flex items-center text-sm">
              <span className={cn(
                "font-medium",
                trend.isPositive ? "text-green-600" : "text-red-600"
              )}>
                {trend.isPositive ? '+' : ''}{trend.value}%
              </span>
              <span className="ml-1 text-gray-500">前週比</span>
            </div>
          )}
        </div>
        <div className={cn("p-3 rounded-full", colorClasses[color])}>
          <Icon className="w-6 h-6 text-white" />
        </div>
      </div>
    </div>
  );
}
```

### LineChart / DoughnutChart

**目的:** Chart.jsを使用したグラフ表示

**ファイル:** `/src/components/Charts/LineChart.tsx`

```typescript
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

interface LineChartProps {
  data: {
    labels: string[];
    datasets: {
      label: string;
      data: number[];
      borderColor: string;
      backgroundColor: string;
    }[];
  };
  title?: string;
}

export function LineChart({ data, title }: LineChartProps) {
  const options = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: !!title,
        text: title,
      },
    },
  };

  return (
    <div className="h-64">
      <Line options={options} data={data} />
    </div>
  );
}
```

## テーブルコンポーネント

### UserTable

**目的:** ユーザー一覧の表示とアクション

**ファイル:** `/src/components/Tables/UserTable.tsx`

```typescript
interface UserTableProps {
  users: User[];
  onEdit: (user: User) => void;
  onDelete: (user: User) => void;
}

export function UserTable({ users, onEdit, onDelete }: UserTableProps) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>ID</TableHead>
          <TableHead>メール</TableHead>
          <TableHead>名前</TableHead>
          <TableHead>ロール</TableHead>
          <TableHead>状態</TableHead>
          <TableHead>作成日</TableHead>
          <TableHead className="text-right">操作</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {users.map((user) => (
          <TableRow key={user.id}>
            <TableCell className="font-mono text-xs">
              {user.id.slice(0, 8)}...
            </TableCell>
            <TableCell>{user.email}</TableCell>
            <TableCell>
              {user.first_name} {user.last_name}
            </TableCell>
            <TableCell>
              <Badge variant={user.role === 'super_admin' ? 'destructive' : 'default'}>
                {user.role}
              </Badge>
            </TableCell>
            <TableCell>
              <Badge variant={user.is_active ? 'default' : 'secondary'}>
                {user.is_active ? '有効' : '無効'}
              </Badge>
            </TableCell>
            <TableCell>{formatDate(user.created_at)}</TableCell>
            <TableCell className="text-right">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onEdit(user)}
              >
                編集
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onDelete(user)}
              >
                削除
              </Button>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
```

## OCR調整コンポーネント

### DocumentPreviewCanvas

**目的:** ドキュメント画像のプレビューと矩形操作

**ファイル:** `/src/components/OCREditor/DocumentPreviewCanvas.tsx`

**主要機能:**

1. **画像表示:** Next.js Imageによる最適化された画像表示
2. **矩形描画:** 既存矩形の視覚化とハイライト
3. **矩形選択:** クリックによる選択とアクションメニュー表示
4. **矩形移動:** ドラッグによる位置調整
5. **矩形リサイズ:** コーナーハンドルによるサイズ変更
6. **新規矩形作成:** 背景ドラッグによる矩形作成
7. **ズーム制御:** +-ボタンによる表示倍率調整
8. **ページナビゲーション:** ◀▶ボタンによるページ切り替え

**構造:**

```typescript
export const DocumentPreviewCanvas: React.FC<Props> = ({
  // 多数のprops...
}) => {
  return (
    <div className="bg-white border rounded-lg flex-1 flex flex-col">
      {/* ヘッダー: ページナビゲーション + ズーム */}
      <div className="px-3 py-2 border-b bg-gray-50">
        <div className="flex items-center justify-between">
          <h3>文書プレビュー - {currentPage.name}</h3>
          <div className="flex items-center gap-2">
            {/* ページナビゲーション */}
            <button onClick={goToPreviousPage}>◀</button>
            <input type="number" value={currentPageNumber} />
            <span>/ {totalPages}</span>
            <button onClick={goToNextPage}>▶</button>

            {/* ズームコントロール */}
            <button onClick={handleZoomOut}>-</button>
            <span>{Math.round(zoomLevel * 100)}%</span>
            <button onClick={handleZoomIn}>+</button>
          </div>
        </div>
      </div>

      {/* プレビューエリア */}
      <div className="flex-1 overflow-auto">
        <div
          ref={previewRef}
          className="relative"
          style={{ width: containerWidth, height: containerHeight }}
          onMouseDown={handleCanvasMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
        >
          {/* 画像 */}
          <Image
            src={currentPage.imagePath}
            alt={currentPage.name}
            width={naturalImageWidth}
            height={naturalImageHeight}
            style={{ width: displayWidth * zoomLevel }}
            onLoad={handleImageLoad}
          />

          {/* 既存矩形の描画 */}
          {rectangles.map(rect => (
            <div
              key={rect.id}
              className={cn(
                "absolute border-2 cursor-move",
                selectedRectId === rect.id ? "border-blue-500" : "border-yellow-400",
                highlightedRectId === rect.id && "ring-4 ring-yellow-300"
              )}
              style={{
                left: rect.x * rectangleScale * zoomLevel,
                top: rect.y * rectangleScale * zoomLevel,
                width: rect.width * rectangleScale * zoomLevel,
                height: rect.height * rectangleScale * zoomLevel,
                backgroundColor: getTypeColor(rect.type),
              }}
              onMouseDown={(e) => handleRectMouseDown(e, rect.id)}
              onClick={(e) => handleRectClick(e, rect.id)}
            >
              {/* ID表示 */}
              <div className="absolute -top-5 left-0 text-xs bg-blue-500 text-white px-1">
                {rect.id}
              </div>

              {/* リサイズハンドル */}
              {selectedRectId === rect.id && (
                <>
                  {['nw', 'ne', 'sw', 'se'].map(handle => (
                    <div
                      key={handle}
                      className={cn("resize-handle", `resize-${handle}`)}
                      onMouseDown={(e) => handleResizeMouseDown(e, handle, rect.id)}
                    />
                  ))}
                </>
              )}

              {/* アクションボタン */}
              {showActionButtons === rect.id && (
                <div className="absolute -bottom-10 left-0 flex gap-1 bg-white shadow-md rounded">
                  <Button
                    size="sm"
                    onClick={() => handleOCR(rect.id)}
                    disabled={!!ocrProcessing}
                  >
                    <CameraIcon className="w-4 h-4" />
                    OCR
                  </Button>
                  <Button
                    size="sm"
                    onClick={() => handleCropImage(rect.id)}
                    disabled={!!cropProcessing}
                  >
                    <ScissorsIcon className="w-4 h-4" />
                    切り出し
                  </Button>
                  <Button
                    size="sm"
                    variant="destructive"
                    onClick={() => handleDeleteClick(rect.id)}
                  >
                    <TrashIcon className="w-4 h-4" />
                  </Button>
                </div>
              )}
            </div>
          ))}

          {/* 新規描画中の矩形 */}
          {isDrawingMode && hasMouseMoved && drawStart && drawEnd && (
            <div
              className="absolute border-2 border-dashed border-green-500 bg-green-100 bg-opacity-30"
              style={{
                left: Math.min(drawStart.x, drawEnd.x) * rectangleScale * zoomLevel,
                top: Math.min(drawStart.y, drawEnd.y) * rectangleScale * zoomLevel,
                width: Math.abs(drawEnd.x - drawStart.x) * rectangleScale * zoomLevel,
                height: Math.abs(drawEnd.y - drawStart.y) * rectangleScale * zoomLevel,
              }}
            />
          )}
        </div>
      </div>
    </div>
  );
};
```

### DocumentStructureSidebar

**目的:** 階層構造のツリー表示

**ファイル:** `/src/components/OCREditor/DocumentStructureSidebar.tsx`

```typescript
interface TreeNodeProps {
  node: PageNode | (Rectangle & { children: Rectangle[] });
  level: number;
  selectedRectId: string | null;
  expandedNodes: Set<string>;
  draggedItem: string | null;
  dragOverItem: string | null;
  dropPosition: "before" | "after" | "inside" | null;
  onSelect: (id: string) => void;
  onToggle: (id: string) => void;
  onDragStart: (e: React.DragEvent, id: string) => void;
  onDragEnd: () => void;
  onDragOver: (e: React.DragEvent, id: string) => void;
  onDragLeave: () => void;
  onDrop: (e: React.DragEvent, id: string) => void;
  onDelete: (id: string) => void;
}

function TreeNode({ node, level, ... }: TreeNodeProps) {
  const isExpanded = expandedNodes.has(node.id);
  const hasChildren = node.children && node.children.length > 0;

  return (
    <div>
      <div
        id={`tree-item-${node.id}`}
        className={cn(
          "flex items-center px-2 py-1 hover:bg-gray-100 cursor-pointer",
          selectedRectId === node.id && "bg-blue-100",
          draggedItem === node.id && "opacity-50"
        )}
        style={{ paddingLeft: `${level * 16}px` }}
        onClick={() => onSelect(node.id)}
        draggable
        onDragStart={(e) => onDragStart(e, node.id)}
        onDragEnd={onDragEnd}
        onDragOver={(e) => onDragOver(e, node.id)}
        onDragLeave={onDragLeave}
        onDrop={(e) => onDrop(e, node.id)}
      >
        {/* 展開/折りたたみボタン */}
        {hasChildren && (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onToggle(node.id);
            }}
            className="mr-1"
          >
            {isExpanded ? <ChevronDownIcon className="w-4 h-4" /> : <ChevronRightIcon className="w-4 h-4" />}
          </button>
        )}

        {/* アイコンとラベル */}
        <span className="text-xs mr-1">{getTypeIcon(node.type)}</span>
        <span className="text-xs flex-1 truncate">{node.id}</span>

        {/* 削除ボタン */}
        <button
          onClick={(e) => {
            e.stopPropagation();
            onDelete(node.id);
          }}
          className="ml-auto opacity-0 group-hover:opacity-100"
        >
          <TrashIcon className="w-3 h-3 text-gray-400 hover:text-red-600" />
        </button>
      </div>

      {/* 子要素を再帰的に表示 */}
      {isExpanded && hasChildren && (
        <div>
          {node.children.map(child => (
            <TreeNode
              key={child.id}
              node={child}
              level={level + 1}
              {...props}
            />
          ))}
        </div>
      )}
    </div>
  );
}

export function DocumentStructureSidebar({ documentTreeData, ... }: Props) {
  return (
    <div className="bg-white border rounded-lg" style={{ height: '60%' }}>
      <div className="px-3 py-2 border-b bg-gray-50">
        <h3 className="text-sm font-semibold">文書構造</h3>
      </div>
      <div ref={scrollAreaRef} className="overflow-auto" style={{ height: 'calc(100% - 40px)' }}>
        {documentTreeData.map(pageNode => (
          <TreeNode
            key={pageNode.id}
            node={pageNode}
            level={0}
            {...props}
          />
        ))}
      </div>
    </div>
  );
}
```

### OCRTextEditor

**目的:** 選択中の要素のテキスト編集

**ファイル:** `/src/components/OCREditor/OCRTextEditor.tsx`

```typescript
export const OCRTextEditor: React.FC<Props> = ({
  currentText,
  currentElementType,
  selectedRectId,
  selectedRectangle,
  ocrProcessing,
  onTextChange,
  onElementTypeChange,
  onTableInfoChange,
  onChangesUpdate,
}) => {
  return (
    <div className="bg-white border rounded-lg flex flex-col" style={{ height: '40%' }}>
      {/* ヘッダー: 要素タイプ選択 */}
      <div className="px-3 py-2 border-b bg-gray-50">
        <h3 className="text-sm font-semibold">OCRテキスト</h3>
        <select
          value={currentElementType}
          onChange={(e) => {
            onElementTypeChange(e.target.value);
            onChangesUpdate(true);
          }}
          disabled={!selectedRectId || !!ocrProcessing}
          className="w-full px-2 py-1 border rounded text-xs mt-1"
        >
          <option value="text">text</option>
          <option value="title">title</option>
          <option value="section_header">section_header</option>
          <option value="list_item">list_item</option>
          <option value="table">table</option>
          <option value="table_cell">table_cell</option>
          {/* ... 他のタイプ ... */}
        </select>
      </div>

      {/* テーブル情報（table_cellの場合） */}
      {currentElementType === 'table_cell' && (
        <div className="px-3 py-2 border-b bg-blue-50">
          <h4 className="text-xs font-semibold text-blue-800 mb-2">テーブル情報</h4>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="block text-xs text-gray-600 mb-1">列番号</label>
              <input
                type="number"
                min="0"
                value={selectedRectangle?.table_info?.col ?? 0}
                onChange={(e) => onTableInfoChange('col', parseInt(e.target.value) || 0)}
                disabled={!selectedRectId || !!ocrProcessing}
                className="w-full px-2 py-1 border rounded text-xs"
              />
            </div>
            <div>
              <label className="block text-xs text-gray-600 mb-1">行番号</label>
              <input
                type="number"
                min="0"
                value={selectedRectangle?.table_info?.row ?? 0}
                onChange={(e) => onTableInfoChange('row', parseInt(e.target.value) || 0)}
                disabled={!selectedRectId || !!ocrProcessing}
                className="w-full px-2 py-1 border rounded text-xs"
              />
            </div>
            <div className="col-span-2">
              <label className="block text-xs text-gray-600 mb-1">セルタイプ</label>
              <select
                value={selectedRectangle?.table_info?.cell_type ?? 'data'}
                onChange={(e) => onTableInfoChange('cell_type', e.target.value)}
                disabled={!selectedRectId || !!ocrProcessing}
                className="w-full px-2 py-1 border rounded text-xs"
              >
                <option value="data">データセル</option>
                <option value="col_header">列ヘッダー</option>
                <option value="row_header">行ヘッダー</option>
              </select>
            </div>
          </div>
        </div>
      )}

      {/* テキスト編集エリア */}
      <div className="p-2 flex-1 flex flex-col">
        <textarea
          value={currentText}
          onChange={(e) => {
            onTextChange(e.target.value);
            onChangesUpdate(true);
          }}
          placeholder="矩形を選択してテキストを編集..."
          disabled={!selectedRectId || !!ocrProcessing}
          className="w-full flex-1 p-2 border rounded text-xs resize-none"
        />
      </div>
    </div>
  );
};
```

### PageListSidebar

**目的:** ページサムネイル一覧

**ファイル:** `/src/components/OCREditor/PageListSidebar.tsx`

```typescript
export const PageListSidebar: React.FC<Props> = ({
  pages,
  currentPageId,
  ocrProcessing,
  setCurrentPageId,
}) => {
  return (
    <div className="w-10 bg-gray-100 border-r flex flex-col items-center py-2 gap-2 overflow-y-auto">
      {pages.map((page, index) => (
        <button
          key={page.id}
          onClick={() => !ocrProcessing && setCurrentPageId(page.id)}
          disabled={!!ocrProcessing}
          className={cn(
            "w-8 h-10 border-2 rounded flex items-center justify-center text-xs font-semibold transition-all",
            currentPageId === page.id
              ? "border-blue-500 bg-blue-100 text-blue-700"
              : "border-gray-300 bg-white text-gray-600 hover:border-blue-300",
            ocrProcessing && "opacity-50 cursor-not-allowed"
          )}
          title={`ページ ${index + 1}`}
        >
          {index + 1}
        </button>
      ))}
    </div>
  );
};
```

## モーダルコンポーネント

### CroppedImageModal

**目的:** 切り出し画像のプレビューと保存

**ファイル:** `/src/components/CroppedImageModal.tsx`

```typescript
interface CroppedImageModalProps {
  isOpen: boolean;
  onClose: () => void;
  imageData: {
    imageData: string; // Base64
    filename: string;
    rectId: string;
  } | null;
  onSave: () => void;
}

export function CroppedImageModal({
  isOpen,
  onClose,
  imageData,
  onSave,
}: CroppedImageModalProps) {
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    if (!imageData) return;

    setSaving(true);
    try {
      // 保存API呼び出し
      await fetch(`/api/documents/${documentId}/save-cropped-image`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          image_data: imageData.imageData,
          filename: imageData.filename,
        }),
      });

      onSave();
      onClose();
    } catch (error) {
      console.error('Save error:', error);
      alert('画像の保存に失敗しました');
    } finally {
      setSaving(false);
    }
  };

  if (!isOpen || !imageData) return null;

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="max-w-4xl">
        <DialogHeader>
          <DialogTitle>切り出し画像</DialogTitle>
          <DialogDescription>{imageData.filename}</DialogDescription>
        </DialogHeader>

        <div className="flex justify-center p-4">
          <img
            src={`data:image/png;base64,${imageData.imageData}`}
            alt="Cropped"
            className="max-w-full max-h-96 border"
          />
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            閉じる
          </Button>
          <Button onClick={handleSave} disabled={saving}>
            {saving ? '保存中...' : '保存'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

## コンポーネント設計原則

### 1. Single Responsibility

各コンポーネントは単一の責務を持つ

```typescript
// Good: 単一責務
function UserAvatar({ user }: { user: User }) {
  return <img src={user.avatar} alt={user.name} />;
}

// Bad: 複数責務
function UserSection({ user }: { user: User }) {
  // アバター表示 + プロフィール編集 + アクティビティ履歴
}
```

### 2. Composition over Inheritance

継承ではなくコンポジションを使用

```typescript
// Good: コンポジション
<Card>
  <CardHeader>
    <CardTitle>タイトル</CardTitle>
  </CardHeader>
  <CardContent>
    コンテンツ
  </CardContent>
</Card>

// Bad: 多重継承
<SpecializedCard title="..." content="..." />
```

### 3. Props Drilling回避

深いネストではContext APIやCustom Hooksを使用

```typescript
// Good: Context使用
const { user } = useAuth();

// Bad: Props drilling
<Parent user={user}>
  <Child user={user}>
    <GrandChild user={user}>
      ...
    </GrandChild>
  </Child>
</Parent>
```

### 4. 型安全性

TypeScriptで厳密な型定義

```typescript
interface ButtonProps {
  variant: 'default' | 'outline' | 'ghost';
  size: 'sm' | 'md' | 'lg';
  onClick: () => void;
  disabled?: boolean;
  children: React.ReactNode;
}
```

## まとめ

Admin Frontendのコンポーネント設計により、以下を実現しています:

1. **再利用性:** shadcn/uiベースの汎用コンポーネント
2. **保守性:** 明確な責務分離と階層構造
3. **拡張性:** Composition パターンによる柔軟な組み合わせ
4. **型安全性:** TypeScriptによる厳密な型定義
5. **一貫性:** 統一されたデザインシステム

これらの設計により、複雑なOCR調整画面を含む全ての管理機能が、保守しやすく拡張可能なコンポーネントで構築されています。