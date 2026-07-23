defmodule Zongzi.Score.Key do
  @moduledoc """
  关于音高的领域模型。

  因为调式的不同，也会采用适配器的模式。

  主要负责两个方面数据的互换：

  * 谱表的数据
  * MIDI/频率的数据

  其以内部类型被保留/序列化。
  """

  @type key_struct :: struct()

  @type t :: key_struct()

  # ---- Basic CRUD ----

  # Create
  @callback new(any()) :: {:ok, key_struct()} | {:error, term()}

  # Save as stub, doesn't requied implementation new. so as from_midi/2
  @callback from_score(score_data :: term(), type :: atom(), ctx :: term()) ::
              {:ok, key_struct()} | {:error, term()}

  @callback from_midi(midi_note :: number(), ctx :: term()) ::
              {:ok, key_struct()} | {:error, term()}

  # 去向
  defprotocol Inner do
    @moduledoc "部分去向的操作集合"

    # ---- 谱表 ----

    @doc "根据谱表类型（如 :staff, :numbered）转换为谱表渲染所需的数据"
    def to_score(key, type, ctx)
    # 比方说十二平均律的钢琴卷帘窗转五线谱就需要调号作为上下文

    # ---- MIDI / Frequency ----

    @doc "Convert into MIDI number(allow float)"
    def to_midi(key)

    @doc "Convert to frequency(Hz)"
    def to_frequency(key, reference)
  end

  # ---- Facade API ----

  def new(attrs, module), do: module.new(attrs)

  def from_score(data, type, ctx, module), do: module.from_score(data, type, ctx)

  def from_midi(midi, ctx, module), do: module.from_midi(midi, ctx)

  defdelegate to_score(key, type, ctx), to: Inner

  defdelegate to_midi(key), to: Inner

  defdelegate to_frequency(key, reference), to: Inner

  defmacro __using__(_opts) do
    quote do
      @behaviour Zongzi.Score.Key
      alias Zongzi.Score.Key.Inner

      @impl true
      def from_score(_score_data, _type, _ctx), do: {:error, :not_implemented}

      @impl true
      def from_midi(_midi, _ctx), do: {:error, :not_implemented}

      defoverridable from_score: 3, from_midi: 2
    end
  end
end
