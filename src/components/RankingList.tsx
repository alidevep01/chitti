import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { PanResponder, StyleSheet, View } from 'react-native';
import { Button, Icon, Text } from 'react-native-paper';
import { brandColors } from '@/theme';
import type { RankingListProps, RankingRow } from './RankingList.types';

function DraggableRow({ row, index, count, disabled, move, targetAt, onLayout }: {
  row: RankingRow; index: number; count: number; disabled: boolean;
  move: (from: number, to: number) => void; targetAt: (from: number, dy: number) => number;
  onLayout: (y: number, height: number) => void;
}) {
  const [active, setActive] = useState(false);
  const held = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const clear = useCallback(() => { clearTimeout(timer.current); held.current = false; setActive(false); }, []);
  useEffect(() => () => clearTimeout(timer.current), []);
  // PanResponder only registers these callbacks; refs are read later during gestures.
  // eslint-disable-next-line react-hooks/refs
  const responder = useMemo(() => PanResponder.create({
    onStartShouldSetPanResponder: () => !disabled,
    onPanResponderGrant: () => { timer.current = setTimeout(() => { held.current = true; setActive(true); }, 300); },
    onPanResponderMove: (_event, gesture) => { if (!held.current && Math.abs(gesture.dy) > 12) clear(); },
    onPanResponderRelease: (_event, gesture) => { if (held.current && !disabled) move(index, targetAt(index, gesture.dy)); clear(); },
    onPanResponderTerminate: clear,
    onPanResponderTerminationRequest: () => !held.current,
  }), [clear, disabled, index, move, targetAt]);
  return <View onLayout={(event) => onLayout(event.nativeEvent.layout.y, event.nativeEvent.layout.height)} style={[styles.row, active && styles.active]}>
    <Text>{row.position}</Text>
    <View {...responder.panHandlers} accessibilityLabel={`Hold and drag ${row.name}`} style={styles.handle}><Icon source="drag-vertical" size={26} /></View>
    <View style={styles.name}><Text>{row.name}</Text><Text variant="bodySmall">{row.detail}</Text></View>
    <View style={styles.actions}><Button disabled={disabled || index === 0} accessibilityLabel={`Move ${row.name} earlier`} onPress={() => move(index, index - 1)}>↑ Earlier</Button><Button disabled={disabled || index === count - 1} accessibilityLabel={`Move ${row.name} later`} onPress={() => move(index, index + 1)}>↓ Later</Button></View>
  </View>;
}

export function RankingList({ rows, disabled, onMove }: RankingListProps) {
  const layouts = useRef<Record<number, { y: number; height: number }>>({});
  const targetAt = (from: number, dy: number) => {
    const start = layouts.current[from];
    if (!start) return from;
    const y = start.y + start.height / 2 + dy;
    return rows.reduce((nearest, _row, index) => {
      const candidate = layouts.current[index];
      const previous = layouts.current[nearest];
      return candidate && previous && Math.abs(y - candidate.y - candidate.height / 2) < Math.abs(y - previous.y - previous.height / 2) ? index : nearest;
    }, from);
  };
  return <View style={styles.list}>{rows.map((row, index) => <DraggableRow key={row.key} row={row} index={index} count={rows.length} disabled={disabled} move={onMove} targetAt={targetAt} onLayout={(y, height) => { layouts.current[index] = { y, height }; }} />)}</View>;
}
const styles = StyleSheet.create({
  list: { gap: 12 }, row: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8, padding: 10, borderWidth: 1, borderColor: brandColors.gold, backgroundColor: brandColors.white },
  active: { backgroundColor: brandColors.lightGold }, handle: { width: 44, height: 48, alignItems: 'center', justifyContent: 'center' },
  name: { flex: 1, minWidth: 130 }, actions: { flexDirection: 'row', flexWrap: 'wrap' },
});
