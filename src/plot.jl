"""
	plot(design, x, y; kwargs...)

Scatter plot of survey design variables `x` and `y`.

The plot takes into account the frequency weights specified by the user
in the design.

```@example plot
apisrs = load_data("apisrs");
srs = SimpleRandomSample(apisrs; weights = :pw);
s = plot(srs, :api99, :api00)
save("scatter.png", s); nothing # hide
```

![](assets/scatter.png)
"""
function plot(design::AbstractSurveyDesign, x::Symbol, y::Symbol; kwargs...)
    data(design.data) * mapping(x, y, markersize = :weights) * visual(Scatter, marker = '￮') |> draw
end

function plot(design::design, x::Symbol, y::Symbol; kwargs...)
	data(design.variables) * mapping(x, y, markersize = :weights) * visual(Scatter, marker = '￮') |> draw
end
