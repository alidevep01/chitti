export type RankingRow = { key: string; name: string; detail: string; position: number };
export type RankingListProps = {
  rows: RankingRow[];
  disabled: boolean;
  onMove: (from: number, to: number) => void;
};
