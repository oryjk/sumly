import { AlertTriangle, CheckCircle2, Info, X } from 'lucide-react';

export type ToastType = 'success' | 'error' | 'info';

export interface ToastItem {
  id: number;
  type: ToastType;
  title: string;
  description?: string;
}

interface ToastStackProps {
  toasts: ToastItem[];
  onDismiss: (id: number) => void;
}

export function ToastStack({ toasts, onDismiss }: ToastStackProps) {
  if (toasts.length === 0) {
    return null;
  }

  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed right-4 top-4 z-50 flex w-[calc(100vw-2rem)] max-w-sm flex-col gap-2.5 sm:right-6 sm:top-6"
    >
      {toasts.map((toast) => {
        const tone =
          toast.type === 'success'
            ? {
                border: 'border-[#3DD68C]/35',
                iconColor: 'text-[#3DD68C]',
                bg: 'bg-[#1B221E]/95',
                Icon: CheckCircle2,
              }
            : toast.type === 'error'
              ? {
                  border: 'border-[#FF5D5D]/40',
                  iconColor: 'text-[#FF5D5D]',
                  bg: 'bg-[#251A1A]/95',
                  Icon: AlertTriangle,
                }
              : {
                  border: 'border-[#F2C512]/35',
                  iconColor: 'text-[#F2C512]',
                  bg: 'bg-[#232018]/95',
                  Icon: Info,
                };

        const { Icon } = tone;

        return (
          <div
            key={toast.id}
            role="status"
            className={`animate-toast-in pointer-events-auto flex items-start gap-3 rounded-xl border ${tone.border} ${tone.bg} px-4 py-3.5 shadow-[0_20px_50px_-18px_rgba(0,0,0,0.85)] backdrop-blur-xl`}
          >
            <Icon className={`mt-0.5 h-5 w-5 shrink-0 ${tone.iconColor}`} />
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium text-[#F5F2EB]">{toast.title}</p>
              {toast.description ? (
                <p className="mt-0.5 text-xs leading-relaxed text-[#B7B0A4]">
                  {toast.description}
                </p>
              ) : null}
            </div>
            <button
              type="button"
              onClick={() => onDismiss(toast.id)}
              aria-label="关闭通知"
              className="rounded-lg p-1 text-[#8D867B] transition hover:bg-white/5 hover:text-[#F5F2EB]"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        );
      })}
    </div>
  );
}
