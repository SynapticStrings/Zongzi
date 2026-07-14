# Slicer 是单向投影

**Status**: Accepted  
**In-tree**: `Score.Slicer`、`Note.slice_flag`

## 决策

- `Slicer.index/2`：`[Note] → [Window{tick_start, tick_end, note_ids}]`，**纯函数、瞬态**。
- 输出无持久 id、不进工程序列化、不与 History 对账。
- `slice_flag`（`:auto | :force_slice | :force_merge`）是切分**输入信号**，不是运行时同步通道。
- 重新切片不得被设计成「更新某个持久短语实体」。

## 澄清

完整**渲染**闭包不是 Slicer 的职责，见 `windowing-post-rebase.md`。  
Slicer 仅保留 note-only / 微缝或草稿用途；默认 phrase 切开用 `Windowing.Strategy`。

## 非目标

- 不在此规定 Caller 如何缓存 phrase。
- 不把引擎后端绑进 Score。
