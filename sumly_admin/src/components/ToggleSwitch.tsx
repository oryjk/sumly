interface ToggleSwitchProps {
  id: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  tone?: 'gold' | 'emerald';
  ariaLabel: string;
}

export function ToggleSwitch({
  id,
  checked,
  onChange,
  disabled = false,
  tone = 'gold',
  ariaLabel,
}: ToggleSwitchProps) {
  const activeTrack =
    tone === 'emerald'
      ? 'bg-[#3DD68C] border-[#3DD68C]/70 shadow-[0_0_20px_rgba(61,214,140,0.35)]'
      : 'bg-[#F2C512] border-[#FFD84D]/70 shadow-[0_0_20px_rgba(242,197,18,0.35)]';

  return (
    <button
      id={id}
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={ariaLabel}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`group relative inline-flex h-8 w-14 shrink-0 cursor-pointer items-center rounded-full border p-1 transition-all duration-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-[#F2C512]/70 focus-visible:ring-offset-2 focus-visible:ring-offset-[#1E1D1B] disabled:cursor-not-allowed disabled:opacity-50 ${
        checked ? activeTrack : 'border-white/12 bg-[#141416] hover:border-white/20'
      }`}
    >
      <span
        aria-hidden="true"
        className={`pointer-events-none inline-block h-6 w-6 rounded-full shadow-md transition-transform duration-200 ease-out ${
          checked
            ? 'translate-x-6 bg-[#141416]'
            : 'translate-x-0 bg-[#9C9588] group-hover:bg-[#CBC5B9]'
        }`}
      />
    </button>
  );
}
