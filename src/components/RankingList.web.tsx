import { useEffect, useRef, useState } from 'react';
import { brandColors } from '@/theme';
import type { RankingListProps } from './RankingList.types';

// Use real DOM pointer events: RN View does not forward HTML drag/drop handlers.
export function RankingList({ rows, disabled, onMove }: RankingListProps) {
  const root = useRef<HTMLDivElement>(null);
  const gesture = useRef<{ from: number; to: number; active: boolean; x: number; y: number; pointer: number } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [highlight, setHighlight] = useState<number | null>(null);
  const [dragging, setDragging] = useState(false);
  const clear = () => {
    clearTimeout(timer.current);
    gesture.current = null;
    setHighlight(null);
    setDragging(false);
  };
  useEffect(() => () => clearTimeout(timer.current), []);
  const targetAt = (y: number) => {
    const nodes = root.current?.querySelectorAll<HTMLElement>('[data-ranking-row]');
    if (!nodes?.length) return 0;
    let nearest = 0;
    let distance = Infinity;
    nodes.forEach((node, index) => {
      const rect = node.getBoundingClientRect();
      const next = Math.abs(y - (rect.top + rect.height / 2));
      if (next < distance) { nearest = index; distance = next; }
    });
    return nearest;
  };
  const buttonStyle = { minWidth: 44, minHeight: 44, border: `1px solid ${brandColors.gold}`, background: brandColors.white, color: brandColors.black, borderRadius: 4, cursor: 'pointer', font: 'inherit', padding: '6px 10px' };
  return <div ref={root} style={{ display: 'grid', gap: 12, fontFamily: 'system-ui, -apple-system, "Segoe UI", sans-serif', fontSize: 14 }}>
    {rows.map((row, index) => <div key={row.key} data-ranking-row style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 10, padding: 10, border: `2px solid ${highlight === index ? brandColors.gold : brandColors.lightGold}`, background: highlight === index ? brandColors.lightGold : brandColors.white, color: brandColors.black }}>
      <span style={{ minWidth: 34, textAlign: 'center', fontWeight: 700 }}>{row.position}</span>
      <button type="button" disabled={disabled} aria-label={`Drag ${row.name} to change payout month`} title="Drag with a mouse, or hold then drag on a touch screen"
        style={{ ...buttonStyle, touchAction: 'none', userSelect: 'none', cursor: dragging ? 'grabbing' : 'grab' }}
        onContextMenu={(event) => event.preventDefault()}
        onKeyDown={(event) => {
          if (event.key === 'Escape') clear();
          if (event.key === 'ArrowUp' || event.key === 'ArrowDown') { event.preventDefault(); onMove(index, index + (event.key === 'ArrowUp' ? -1 : 1)); }
        }}
        onPointerDown={(event) => {
          if (disabled || !event.isPrimary || event.button !== 0) return;
          event.currentTarget.setPointerCapture(event.pointerId);
          gesture.current = { from: index, to: index, active: event.pointerType === 'mouse', x: event.clientX, y: event.clientY, pointer: event.pointerId };
          if (event.pointerType === 'mouse') { setHighlight(index); setDragging(true); }
          else timer.current = setTimeout(() => { if (gesture.current) { gesture.current.active = true; setHighlight(index); setDragging(true); } }, 300);
        }}
        onPointerMove={(event) => {
          const drag = gesture.current;
          if (!drag || drag.pointer !== event.pointerId) return;
          if (!drag.active) {
            if (Math.hypot(event.clientX - drag.x, event.clientY - drag.y) > 12) clear();
            return;
          }
          drag.to = targetAt(event.clientY);
          setHighlight(drag.to);
        }}
        onPointerUp={(event) => {
          const drag = gesture.current;
          if (drag?.active && !disabled) onMove(drag.from, targetAt(event.clientY));
          clear();
        }}
        onPointerCancel={clear} onLostPointerCapture={clear}>⠿</button>
      <div style={{ flex: '1 1 180px', overflowWrap: 'anywhere' }}><div style={{ fontWeight: 600 }}>{row.name}</div><div style={{ fontSize: 13 }}>{row.detail}</div></div>
      <div style={{ display: 'flex', gap: 6, marginLeft: 'auto' }}>
        <button type="button" style={buttonStyle} disabled={disabled || index === 0} aria-label={`Move ${row.name} earlier`} onClick={() => onMove(index, index - 1)}>↑ Earlier</button>
        <button type="button" style={buttonStyle} disabled={disabled || index === rows.length - 1} aria-label={`Move ${row.name} later`} onClick={() => onMove(index, index + 1)}>↓ Later</button>
      </div>
    </div>)}
    <div role="status" aria-live="polite" style={{ fontSize: 13, color: brandColors.black }}>{dragging && highlight !== null ? `Release to move to month ${rows[highlight]?.position}` : 'Drag the grip to reorder. On touch screens, hold the grip briefly first. Arrow buttons also work.'}</div>
  </div>;
}
