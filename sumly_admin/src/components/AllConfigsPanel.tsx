import { useMemo, useState } from 'react';
import {
  AlertCircle,
  Braces,
  Check,
  Clock,
  Edit3,
  Layers,
  Loader2,
  Plus,
  Save,
  Sparkles,
  User,
  X,
} from 'lucide-react';
import {
  EXTENSION_JSON_MAX_BYTES,
  isRecord,
  MEMBERSHIP_PAYWALL_KEY,
  type AppConfigItem,
} from '../types/config';
import { formatBeijingTime, getUtf8ByteLength } from '../utils/format';

interface AllConfigsPanelProps {
  configs: AppConfigItem[];
  onSaveConfig: (
    key: string,
    value: Record<string, unknown>,
    description: string,
    note: string,
  ) => Promise<boolean>;
}

interface EditorState {
  mode: 'edit' | 'create';
  key: string;
  description: string;
  jsonText: string;
  note: string;
}

const KEY_PATTERN = /^[a-z][a-z0-9_.-]{1,63}$/;

export function AllConfigsPanel({ configs, onSaveConfig }: AllConfigsPanelProps) {
  const [includeCore, setIncludeCore] = useState(false);
  const [editor, setEditor] = useState<EditorState | null>(null);
  const [saving, setSaving] = useState(false);

  const visibleConfigs = useMemo(() => {
    const filtered = includeCore
      ? configs
      : configs.filter((item) => item.key !== MEMBERSHIP_PAYWALL_KEY);
    return [...filtered].sort((a, b) => a.key.localeCompare(b.key));
  }, [configs, includeCore]);

  const jsonValidation = useMemo(() => {
    if (!editor) {
      return { valid: false, error: null as string | null, bytes: 0, parsed: null as Record<string, unknown> | null };
    }
    const bytes = getUtf8ByteLength(editor.jsonText);
    if (bytes > EXTENSION_JSON_MAX_BYTES) {
      return {
        valid: false,
        error: `JSON 体积超出 16KB 限制（当前 ${(bytes / 1024).toFixed(2)} KB）`,
        bytes,
        parsed: null,
      };
    }
    try {
      const parsed: unknown = JSON.parse(editor.jsonText);
      if (!isRecord(parsed)) {
        return {
          valid: false,
          error: '顶层配置值必须为合法 JSON 对象（例如 { "enabled": true }）',
          bytes,
          parsed: null,
        };
      }
      return { valid: true, error: null, bytes, parsed };
    } catch (error) {
      return {
        valid: false,
        error: error instanceof Error ? `JSON 语法错误：${error.message}` : 'JSON 语法错误',
        bytes,
        parsed: null,
      };
    }
  }, [editor]);

  const keyError = useMemo(() => {
    if (!editor || editor.mode !== 'create') {
      return null;
    }
    const trimmed = editor.key.trim();
    if (!trimmed) {
      return '请输入配置 Key';
    }
    if (trimmed === MEMBERSHIP_PAYWALL_KEY) {
      return '请通过「功能开关工作台」修改 membership_paywall';
    }
    if (!KEY_PATTERN.test(trimmed)) {
      return '仅允许小写字母开头，含小写字母、数字、下划线、点或短横线（2~64 位）';
    }
    return null;
  }, [editor]);

  function openEdit(item: AppConfigItem) {
    setEditor({
      mode: 'edit',
      key: item.key,
      description: item.description,
      jsonText: JSON.stringify(item.value, null, 2),
      note: '',
    });
  }

  function openCreate() {
    setEditor({
      mode: 'create',
      key: '',
      description: '',
      jsonText: JSON.stringify({ enabled: false }, null, 2),
      note: '新增扩展配置',
    });
  }

  function handleFormatJson() {
    if (!editor || !jsonValidation.valid || !jsonValidation.parsed) {
      return;
    }
    setEditor({
      ...editor,
      jsonText: JSON.stringify(jsonValidation.parsed, null, 2),
    });
  }

  async function handleSave() {
    if (!editor || !jsonValidation.valid || !jsonValidation.parsed || keyError) {
      return;
    }
    setSaving(true);
    try {
      const ok = await onSaveConfig(
        editor.key.trim(),
        jsonValidation.parsed,
        editor.description.trim(),
        editor.note.trim(),
      );
      if (ok) {
        setEditor(null);
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="gold-card rounded-2xl p-5 sm:p-6">
      {/* Header */}
      <div className="flex flex-col gap-3 border-b border-white/8 pb-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-[#F2C512]/25 bg-[#F2C512]/10 text-[#F2C512]">
            <Layers className="h-4 w-4" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-base font-semibold text-[#F5F2EB]">
                扩展配置管理（All Configs）
              </h3>
              <span className="rounded-full border border-white/10 bg-white/5 px-2 py-0.5 font-mono text-[11px] text-[#B8B1A5]">
                {visibleConfigs.length} 项
              </span>
            </div>
            <p className="text-xs text-[#958E82]">
              统一查看与 JSON 校验编辑服务端全部动态配置项，便于未来横向扩展新业务开关
            </p>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2.5">
          <label className="inline-flex cursor-pointer items-center gap-2 rounded-xl border border-white/8 bg-[#141416] px-3 py-1.5 text-xs text-[#BFB8AC]">
            <input
              type="checkbox"
              checked={includeCore}
              onChange={(e) => setIncludeCore(e.target.checked)}
              className="h-3.5 w-3.5 rounded accent-[#F2C512]"
            />
            包含核心配置
          </label>

          <button
            type="button"
            onClick={openCreate}
            className="inline-flex cursor-pointer items-center gap-1.5 rounded-xl border border-[#F2C512]/35 bg-[#F2C512]/12 px-3.5 py-1.5 text-xs font-semibold text-[#FFE066] transition hover:bg-[#F2C512]/20"
          >
            <Plus className="h-3.5 w-3.5" />
            新增扩展配置
          </button>
        </div>
      </div>

      {/* Editor Drawer / Card */}
      {editor ? (
        <div className="mt-5 rounded-2xl border border-[#F2C512]/30 bg-[#141416] p-4 sm:p-5">
          <div className="flex items-center justify-between gap-2 border-b border-white/8 pb-3">
            <div className="flex items-center gap-2">
              <Braces className="h-4 w-4 text-[#F2C512]" />
              <h4 className="text-sm font-semibold text-[#F5F2EB]">
                {editor.mode === 'create'
                  ? '新增扩展配置项'
                  : `编辑配置：${editor.key}`}
              </h4>
            </div>
            <button
              type="button"
              onClick={() => setEditor(null)}
              disabled={saving}
              aria-label="关闭编辑器"
              className="rounded-lg p-1 text-[#8A8377] transition hover:bg-white/5 hover:text-[#F5F2EB]"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          <div className="mt-4 grid gap-4 sm:grid-cols-2">
            <div>
              <label className="mb-1.5 block text-xs font-medium text-[#CBC4B7]">
                配置 Key
              </label>
              <input
                type="text"
                value={editor.key}
                disabled={editor.mode === 'edit' || saving}
                onChange={(e) => setEditor({ ...editor, key: e.target.value })}
                placeholder="例如：gold_alert_banner"
                className="w-full rounded-xl border border-white/10 bg-[#1B1A18] px-3.5 py-2 font-mono text-xs text-[#F5F2EB] placeholder:text-[#655F56] focus:border-[#F2C512]/60 focus:outline-none disabled:opacity-60"
              />
              {keyError ? (
                <p className="mt-1 text-[11px] text-[#FF8B8B]">{keyError}</p>
              ) : null}
            </div>

            <div>
              <label className="mb-1.5 block text-xs font-medium text-[#CBC4B7]">
                配置说明（Description）
              </label>
              <input
                type="text"
                value={editor.description}
                disabled={saving}
                onChange={(e) => setEditor({ ...editor, description: e.target.value })}
                placeholder="描述该配置项用途"
                className="w-full rounded-xl border border-white/10 bg-[#1B1A18] px-3.5 py-2 text-xs text-[#F5F2EB] placeholder:text-[#655F56] focus:border-[#F2C512]/60 focus:outline-none"
              />
            </div>
          </div>

          <div className="mt-4">
            <div className="mb-1.5 flex flex-wrap items-center justify-between gap-2">
              <label className="text-xs font-medium text-[#CBC4B7]">
                配置值（JSON Object，上限 16 KB）
              </label>
              <div className="flex items-center gap-3">
                <span
                  className={`font-mono text-[11px] tabular-nums ${
                    jsonValidation.bytes > EXTENSION_JSON_MAX_BYTES
                      ? 'text-[#FF5D5D]'
                      : 'text-[#8D867B]'
                  }`}
                >
                  {jsonValidation.bytes} / {EXTENSION_JSON_MAX_BYTES} B
                </span>
                <button
                  type="button"
                  disabled={!jsonValidation.valid || saving}
                  onClick={handleFormatJson}
                  className="inline-flex cursor-pointer items-center gap-1 rounded-md border border-white/10 bg-white/[0.04] px-2 py-0.5 text-[11px] text-[#D8D1C5] transition hover:border-[#F2C512]/40 hover:text-[#F2C512] disabled:cursor-not-allowed disabled:opacity-40"
                >
                  <Sparkles className="h-3 w-3" />
                  格式化 JSON
                </button>
              </div>
            </div>

            <textarea
              rows={8}
              spellCheck={false}
              value={editor.jsonText}
              disabled={saving}
              onChange={(e) => setEditor({ ...editor, jsonText: e.target.value })}
              className={`w-full rounded-xl border bg-[#0F0F11] p-3.5 font-mono text-xs leading-relaxed text-[#EFE9DC] focus:outline-none focus:ring-2 ${
                jsonValidation.valid
                  ? 'border-white/10 focus:border-[#F2C512]/60 focus:ring-[#F2C512]/20'
                  : 'border-[#FF5D5D]/50 focus:border-[#FF5D5D] focus:ring-[#FF5D5D]/20'
              }`}
            />

            <div className="mt-2 flex items-center gap-1.5 text-xs">
              {jsonValidation.valid ? (
                <span className="inline-flex items-center gap-1 text-[#3DD68C]">
                  <Check className="h-3.5 w-3.5" />
                  JSON 对象校验通过
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 text-[#FF8B8B]">
                  <AlertCircle className="h-3.5 w-3.5" />
                  {jsonValidation.error}
                </span>
              )}
            </div>
          </div>

          <div className="mt-4 flex flex-col gap-3 border-t border-white/8 pt-4 sm:flex-row sm:items-end sm:justify-between">
            <div className="flex-1">
              <label className="mb-1.5 block text-xs font-medium text-[#CBC4B7]">
                变更备注（可选）
              </label>
              <input
                type="text"
                maxLength={120}
                value={editor.note}
                disabled={saving}
                onChange={(e) => setEditor({ ...editor, note: e.target.value })}
                placeholder="记录本次配置修改原因"
                className="w-full rounded-xl border border-white/10 bg-[#1B1A18] px-3.5 py-2 text-xs text-[#F5F2EB] placeholder:text-[#655F56] focus:border-[#F2C512]/60 focus:outline-none"
              />
            </div>

            <div className="flex items-center justify-end gap-2.5">
              <button
                type="button"
                onClick={() => setEditor(null)}
                disabled={saving}
                className="cursor-pointer rounded-xl border border-white/10 bg-[#1B1A18] px-4 py-2 text-xs font-medium text-[#CBC4B7] transition hover:text-[#F5F2EB]"
              >
                取消
              </button>
              <button
                type="button"
                onClick={handleSave}
                disabled={!jsonValidation.valid || Boolean(keyError) || saving}
                className="gold-btn inline-flex cursor-pointer items-center gap-1.5 rounded-xl px-4 py-2 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-45"
              >
                {saving ? (
                  <>
                    <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    保存中...
                  </>
                ) : (
                  <>
                    <Save className="h-3.5 w-3.5" />
                    保存配置
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      {/* Config List */}
      {visibleConfigs.length === 0 ? (
        <div className="mt-5 flex flex-col items-center justify-center rounded-xl border border-dashed border-white/10 bg-[#141416]/60 px-4 py-12 text-center">
          <Braces className="h-8 w-8 text-[#59534A]" />
          <p className="mt-3 text-sm font-medium text-[#C2BBB0]">
            当前暂无其他扩展配置项
          </p>
          <p className="mt-1 max-w-md text-xs leading-relaxed text-[#847D72]">
            核心开关 <code className="font-mono text-[#F2C512]">membership_paywall</code> 请在「功能开关工作台」操作；
            如需新增业务开关，可点击右上角「新增扩展配置」直接创建。
          </p>
        </div>
      ) : (
        <div className="mt-5 grid gap-4 md:grid-cols-2">
          {visibleConfigs.map((item) => {
            const isCore = item.key === MEMBERSHIP_PAYWALL_KEY;
            return (
              <article
                key={item.key}
                className="flex flex-col justify-between rounded-xl border border-white/8 bg-[#161513] p-4 transition hover:border-[#F2C512]/28"
              >
                <div>
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <code className="truncate font-mono text-sm font-semibold text-[#F2C512]">
                          {item.key}
                        </code>
                        {isCore ? (
                          <span className="rounded-full border border-[#F2C512]/30 bg-[#F2C512]/12 px-2 py-0.5 text-[10px] font-medium text-[#FFE066]">
                            核心配置
                          </span>
                        ) : null}
                      </div>
                      <p className="mt-1 text-xs text-[#9D968A]">
                        {item.description || '暂无配置描述'}
                      </p>
                    </div>

                    <button
                      type="button"
                      onClick={() => openEdit(item)}
                      className="inline-flex shrink-0 cursor-pointer items-center gap-1 rounded-lg border border-white/10 bg-[#1E1D1B] px-2.5 py-1.5 text-xs font-medium text-[#DDD6C9] transition hover:border-[#F2C512]/45 hover:text-[#F2C512]"
                    >
                      <Edit3 className="h-3.5 w-3.5" />
                      编辑 JSON
                    </button>
                  </div>

                  <pre className="mt-3 max-h-48 overflow-auto rounded-lg border border-white/6 bg-[#101012] p-3 font-mono text-[11px] leading-relaxed text-[#DCD5C8]">
                    {JSON.stringify(item.value, null, 2)}
                  </pre>
                </div>

                <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-white/6 pt-2.5 text-[11px] text-[#888176]">
                  <span className="inline-flex items-center gap-1">
                    <User className="h-3 w-3" />
                    {item.updated_by || 'system'}
                  </span>
                  <span className="inline-flex items-center gap-1 font-mono tabular-nums">
                    <Clock className="h-3 w-3" />
                    {formatBeijingTime(item.updated_at)}
                  </span>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}
