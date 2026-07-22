defmodule Zongzi.MixProject do
  use Mix.Project

  def project do
    [
      app: :zongzi,
      version: "0.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: [precommit: ["compile --warnings-as-errors", "format", "test"]],
      deps: deps(),
      docs: docs()
    ]
  end

  def application, do: []

  def cli, do: [preferred_envs: [precommit: :test]]

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  @extras_docs [
    "docs/en/guide/Overview.md",
    # Chinese doc
    "docs/zh/guide/Overview-zh.md",
    "docs/zh/guide/TheLittleZongzi-zh.md",
    "docs/zh/guide/CallerDesigning-zh.md"
  ]

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "README.zh-CN.md", "CHANGELOG.md"] ++ @extras_docs,
      before_closing_head_tag: &before_closing_head_tag/1,
      groups_for_modules: [
        Timeline: [
          Zongzi.Timeline,
          Zongzi.Timeline.SeqID,
          Zongzi.Timeline.Query,
          Zongzi.Timeline.Neighborhood
        ],
        Anchor: [
          Zongzi.Anchor,
          Zongzi.Anchor.Strategy,
          Zongzi.Anchor.Context,
          Zongzi.Anchor.NoteTriplet,
          Zongzi.Anchor.ScoredHost,
          Zongzi.Anchor.TripletMatch
        ],
        Intervention: [
          Zongzi.Intervention,
          Zongzi.Intervention.Declaration
        ],
        Score: [
          Zongzi.Score,
          Zongzi.Score.Key,
          Zongzi.Score.Key.Inner,
          Zongzi.Score.Key.TwelveET,
          Zongzi.Score.Note,
          Zongzi.Score.Grid
        ],
        "Score Timing": [
          Zongzi.Score.Tick,
          Zongzi.Score.Record,
          Zongzi.Score.RecordMap,
          Zongzi.Score.Tempo,
          Zongzi.Score.Tempo.Event,
          Zongzi.Score.Tempo.Segment,
          Zongzi.Score.TempoMap,
          Zongzi.Score.Tempo.Linear,
          Zongzi.Score.Tempo.Step,
          Zongzi.Score.TimeSig,
          Zongzi.Score.TimeSigMap
        ],
        Windowing: [
          Zongzi.Windowing,
          Zongzi.Windowing.Context,
          Zongzi.Windowing.Segment,
          Zongzi.Windowing.Strategy,
          Zongzi.Windowing.WholeTrack,
          Zongzi.Windowing.RestSplit3Beats
        ],
        Engine: [
          Zongzi.Engine
        ],
        Curve: [
          Zongzi.Curve,
          Zongzi.Curve.Adapter,
          Zongzi.Curve.Chunk,
          Zongzi.Curve.ControlPoint,
          Zongzi.Curve.Adapter.Bezier,
          Zongzi.Curve.Adapter.CatmullRom
        ],
        Utilities: [
          Zongzi.Helpers,
          Zongzi.Util.ID,
          Zongzi.Util.Model,
          Zongzi.Util.Object
        ]
      ],
      groups_for_extras: [
        "English Documents": [~r/docs\/en\/.?/],
        中文文档: [~r/docs\/zh\/.?/]
      ],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md"
      ]
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <!--MathJax-->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.4/dist/katex.min.css" integrity="sha384-vKruj+a13U8yHIkAyGgK1J3ArTLzrFGBbBc0tDp4ad/EyewESeXE/Iv67Aj8gKZ0" crossorigin="anonymous">
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.4/dist/katex.min.js" integrity="sha384-PwRUT/YqbnEjkZO0zZxNqcxACrXe+j766U2amXcgMg5457rve2Y7I6ZJSm2A0mS4" crossorigin="anonymous"></script>
    <link href="https://cdn.jsdelivr.net/npm/katex-copytex@1.0.2/dist/katex-copytex.min.css" rel="stylesheet" type="text/css">
    <script defer src="https://cdn.jsdelivr.net/npm/katex-copytex@1.0.2/dist/katex-copytex.min.js" crossorigin="anonymous"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.4/dist/contrib/auto-render.min.js" integrity="sha384-+VBxd3r6XgURycqtZ117nYw44OOcIax56Z4dCRWbxyPt0Koah1uHoK0o4+/RRE05" crossorigin="anonymous"></script>
    <script>
      window.addEventListener("exdoc:loaded", () => {
        renderMathInElement(document.body, {
          delimiters: [
            {left: '$$', right: '$$', display: true},
            {left: '$', right: '$', display: false},
          ]
        })
      })
    </script>
    <!--Mermaid-->
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_head_tag(:epub), do: ""
end
