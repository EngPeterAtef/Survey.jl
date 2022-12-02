"""
    AbstractSurveyDesign

Supertype for every survey design type. 

!!! note

    The data passed to a survey constructor is modified. To avoid this pass a copy of the data
    instead of the original.
"""
abstract type AbstractSurveyDesign end

"""
    SimpleRandomSample <: AbstractSurveyDesign


A simple random sample dataset can be loaded from a data frame into a `SimpleRandomSample` object for downstream analyses. 

# Arguments:
`data::AbstractDataFrame`: the survey dataset (!this gets modified by the constructor).
`sampsize::Union{Nothing,Symbol,<:Unsigned,Vector{<:Real}}=UInt(nrow(data))`:  the survey sample size.
`popsize::Union{Nothing,Symbol,<:Unsigned,Vector{<:Real}}=nothing`: the (expected) survey population size.
`weights::Union{Nothing,Symbol,Vector{<:Real}}=nothing`: the sampling weights.
`probs::Union{Nothing,Symbol,Vector{<:Real}}=nothing: the sampling probabilities.
`ignorefpc=false`: choose to ignore finite population correction and assume all weights equal to 1.0

The precedence order of using `popsize`, `weights` and `probs` is `popsize` > `weights` > `probs`.
E.g. If `popsize` is given then it is assumed to be the ground truth over `weights` or `probs`.

If `popsize` is not given `weights` or `probs` must be given. `popsize` is then calculated
using the weights and the sample size.

```jldoctest
julia> apisrs = load_data("apisrs");

julia> srs = SimpleRandomSample(apisrs; popsize=:fpc)
julia> srs
SimpleRandomSample:
data: 200x42 DataFrame
weights: 31.0, 31.0, 31.0, ..., 31.0
probs: 0.0323, 0.0323, 0.0323, ..., 0.0323
fpc: 6194, 6194, 6194, ..., 6194
popsize: 6194
sampsize: 200
sampfraction: 0.0323
ignorefpc: false
```
"""
struct SimpleRandomSample <: AbstractSurveyDesign
    data::AbstractDataFrame
    sampsize::Union{Unsigned,Nothing}
    popsize::Union{Unsigned,Nothing}
    sampfraction::Float64
    fpc::Float64
    ignorefpc::Bool
    function SimpleRandomSample(data::AbstractDataFrame;
        popsize=nothing,
        sampsize=nrow(data) |> UInt,
        weights=nothing,
        probs=nothing,
        ignorefpc=false
    )
        # Only valid argument types given to constructor
        argtypes_weights = Union{Nothing,Symbol,Vector{<:Real}}
        argtypes_probs = Union{Nothing,Symbol,Vector{<:Real}}
        argtypes_popsize = Union{Nothing,Symbol,<:Unsigned,Vector{<:Real}}
        argtypes_sampsize = Union{Nothing,Symbol,<:Unsigned,Vector{<:Real}}
        # If any invalid type raise error
        if !(isa(weights, argtypes_weights))
            error("invalid type of argument given for `weights` argument")
        elseif !(isa(probs, argtypes_probs))
            error("invalid type of argument given for `probs` argument")
        elseif !(isa(popsize, argtypes_popsize))
            error("invalid type of argument given for `popsize` argument")
        elseif !(isa(sampsize, argtypes_sampsize))
            error("invalid type of argument given for `sampsize` argument")
        end
        # If any of weights or probs given as Symbol,
        # find the corresponding column in `data`
        if isa(weights, Symbol)
            weights = data[!, weights]
        end
        if isa(probs, Symbol)
            probs = data[!, probs]
        end
        # If weights/probs vector not numeric/real, ie. string column passed for weights, then raise error
        if !isa(weights, Union{Nothing,Vector{<:Real}})
            error("weights should be Vector{<:Real}. You passed $(typeof(weights))")
        elseif !isa(probs, Union{Nothing,Vector{<:Real}})
            error("sampling probabilities should be Vector{<:Real}. You passed $(typeof(probs))")
        end
        # If popsize given as Symbol or Vector, check all records equal 
        if isa(popsize, Symbol)
            if !all(w -> w == first(data[!, popsize]), data[!, popsize])
                error("popsize must be same for all observations in Simple Random Sample")
            end
            popsize = first(data[!, popsize]) |> UInt
        elseif isa(popsize, Vector{<:Real})
            if !all(w -> w == first(popsize), popsize)
                error("popsize must be same for all observations in Simple Random Sample")
            end
            popsize = first(popsize) |> UInt
        end
        # If sampsize given as Symbol or Vector, check all records equal 
        if isa(sampsize, Symbol)
            if !all(w -> w == first(data[!, sampsize]), data[!, sampsize])
                error("sampsize must be same for all observations in Simple Random Sample")
            end
            sampsize = first(data[!, sampsize]) |> UInt
        elseif isa(sampsize, Vector{<:Real})
            if !all(w -> w == first(sampsize), sampsize)
                error("sampsize must be same for all observations in Simple Random Sample")
            end
            sampsize = first(sampsize) |> UInt
        end
        # If both `weights` and `probs` given, then `weights` is assumed to be ground truth for probs.
        if !isnothing(weights) && !isnothing(probs)
            probs = 1 ./ weights
            data[!, :probs] = probs
        end
        # popsize must be nothing or <:Unsigned by now
        if isnothing(popsize)
            # If popsize not given, fallback to weights, probs and sampsize to estimate `popsize`
            @warn "popsize not given. using weights/probs and sampsize to estimate `popsize`"
            # Check that all weights (or probs if weights not given) are equal, as SRS is by definition equi-weighted
            if typeof(weights) <: Vector{<:Real}
                if !all(w -> w == first(weights), weights)
                    error("all frequency weights must be equal for Simple Random Sample")
                end
            elseif typeof(probs) <: Vector{<:Real}
                if !all(p -> p == first(probs), probs)
                    error("all probability weights must be equal for Simple Random Sample")
                end
                weights = 1 ./ probs
            else
                error("either weights or probs must be given if `popsize` not given")
            end
            # Estimate population size
            popsize = round(sampsize * first(weights)) |> UInt
        elseif typeof(popsize) <: Unsigned
            weights = fill(popsize / sampsize, nrow(data)) # If popsize is given, weights vector is made concordant with popsize and sampsize, regardless of given weights argument
            probs = 1 ./ weights
        else
            error("something went wrong, please check validity of inputs.")
        end
        # If sampsize greater than popsize than illogical arguments specified.
        if sampsize > popsize
            error("population size was estimated to be less than given sampsize. Please check input arguments.")
        end
        # If ignorefpc then set weights to 1 ??
        # TODO: This works under some cases, but should find better way to process ignoring fpc
        if ignorefpc
            @warn "assuming all weights are equal to 1.0"
            weights = ones(nrow(data))
            probs = 1 ./ weights
        end
        # sum of weights must equal to `popsize` for SRS
        if !isnothing(weights) && !(isapprox(sum(weights), popsize; atol=1e-4))
            if ignorefpc && !(isapprox(sum(weights), sampsize; atol=1e-4)) # Change if ignorefpc functionality changes
                error("sum of sampling weights should be equal to `sampsize` for `SimpleRandomSample` with `ignorefpc`")
            elseif !ignorefpc
                @show sum(weights)
                error("sum of sampling weights must be equal to `popsize` for `SimpleRandomSample`")
            end
        end
        # sum of probs must equal popsize for SRS
        if !isnothing(probs) && !(isapprox(sum(1 ./ probs), popsize; atol=1e-4))
            if ignorefpc && !(isapprox(sum(1 ./ probs), sampsize; atol=1e-4)) # Change if ignorefpc functionality changes
                error("sum of inverse sampling probabilities should be equal to `sampsize` for `SimpleRandomSample` with `ignorefpc`")
            elseif !ignorefpc
                @show sum(1 ./ probs)
                error("sum of inverse of sampling probabilities must be equal to `popsize` for Simple Random Sample")
            end
        end
        ## Set remaining parts of data structure
        # set sampling fraction
        sampfraction = sampsize / popsize
        # set fpc
        fpc = ignorefpc ? 1 : 1 - (sampsize / popsize)
        # add columns for frequency and probability weights to `data`
        data[!, :weights] = weights
        if isnothing(probs)
            probs = 1 ./ data[!, :weights]
        end
        data[!, :probs] = probs
        # Initialise the structure
        new(data, sampsize, popsize, sampfraction, fpc, ignorefpc)
    end
end

"""
    StratifiedSample <: AbstractSurveyDesign

A stratified sample dataset can be loaded from a data frame into a `StatifiedSample` object for downstream analyses. 

`strata` must be specified as a Symbol name of a column in `data`.

# Arguments:
`data::AbstractDataFrame`: the survey dataset (!this gets modified by the constructor).
`strata::Symbol`: the stratification variable - must be given as a column in `data`.
`sampsize::Union{Nothing,Symbol,<:Unsigned,Vector{<:Real}}=UInt(nrow(data))`:  the survey sample size.
`popsize::Union{Nothing,Symbol,<:Unsigned,Vector{<:Real}}=nothing`: the (expected) survey population size.
`weights::Union{Nothing,Symbol,Vector{<:Real}}=nothing`: the sampling weights.
`probs::Union{Nothing,Symbol,Vector{<:Real}}=nothing: the sampling probabilities.
`ignorefpc=false`: choose to ignore finite population correction and assume all weights equal to 1.0

The `popsize`, `weights` and `probs` parameters follow the same rules as for [`SimpleRandomSample`](@ref).

```jldoctest
julia> apistrat = load_data("apistrat");

julia> dstrat = StratifiedSample(apistrat, :stype; popsize=:fpc)
julia> dstrat
StratifiedSample:
data: 200x45 DataFrame
strata: stype
weights: 44.2, 44.2, 44.2, ..., 15.1
probs: 0.0226, 0.0226, 0.0226, ..., 0.0662
fpc: 0.977, 0.977, 0.977, ..., 0.934
popsize: 4421, 4421, 4421, ..., 755
sampsize: 100, 100, 100, ..., 50
sampfraction: 0.0226, 0.0226, 0.0226, ..., 0.0662
ignorefpc: false
```
"""
struct StratifiedSample <: AbstractSurveyDesign
    data::AbstractDataFrame
    strata::Symbol
    ignorefpc::Bool
    function StratifiedSample(data::AbstractDataFrame, strata::Symbol;
        popsize=nothing,
        sampsize=nothing,
        weights=nothing,
        probs=nothing,
        ignorefpc=false
    )
        # Only valid argument types given to constructor
        argtypes_weights = Union{Nothing,Symbol,Vector{<:Real}}
        argtypes_probs = Union{Nothing,Symbol,Vector{<:Real}}
        argtypes_popsize = Union{Nothing,Symbol}
        argtypes_sampsize = Union{Nothing,Symbol}
        # If any invalid type raise error
        if !(isa(weights, argtypes_weights))
            error("invalid type of argument given for `weights` argument")
        elseif !(isa(probs, argtypes_probs))
            error("invalid type of argument given for `probs` argument")
        elseif !(isa(popsize, argtypes_popsize))
            error("invalid type of argument given for `popsize` argument. Please give Symbol of the column in data")
        elseif !(isa(sampsize, argtypes_sampsize))
            error("invalid type of argument given for `sampsize` argument. Please give Symbol of the column in data")
        end
        # Store the iterator over each strata, as used multiple times
        data_groupedby_strata = groupby(data, strata)
        # If any of weights or probs given as Symbol, find the corresponding column in `data`
        if isa(weights, Symbol)
            for each_strata in keys(data_groupedby_strata)
                if !all(w -> w == first(data_groupedby_strata[each_strata][!, weights]), data_groupedby_strata[each_strata][!, weights])
                    error("sampling weights within each strata must be equal in StratifiedSample")
                end
            end
            # original_weights_colname = copy(weights)
            weights = data[!, weights] # If all good with weights column, then store it as Vector
        end
        if isa(probs, Symbol)
            for each_strata in keys(data_groupedby_strata)
                if !all(p -> p == first(data_groupedby_strata[each_strata][!, probs]), data_groupedby_strata[each_strata][!, probs])
                    error("sampling probabilities within each strata must be equal in StratifiedSample")
                end
            end
            # original_probs_colname = copy(probs)
            probs = data[!, probs] # If all good with probs column, then store it as Vector
        end
        # If weights/probs vector not numeric/real, ie. string column passed for weights, then raise error
        if !isa(weights, Union{Nothing,Vector{<:Real}})
            error("weights should be Vector{<:Real}. You passed $(typeof(weights))")
        elseif !isa(probs, Union{Nothing,Vector{<:Real}})
            error("sampling probabilities should be Vector{<:Real}. You passed $(typeof(probs))")
        end
        # If popsize given as Symbol or Vector, check all records equal in each strata
        if isa(popsize, Symbol)
            for each_strata in keys(data_groupedby_strata)
                if !all(w -> w == first(data_groupedby_strata[each_strata][!, popsize]), data_groupedby_strata[each_strata][!, popsize])
                    error("popsize must be same for all observations within each strata in StratifiedSample")
                end
            end
            # original_popsize_colname = copy(popsize)
            popsize = data[!, popsize]
        end
        # If sampsize given as Symbol or Vector, check all records equal 
        if isa(sampsize, Symbol)
            if isnothing(popsize) && isnothing(weights) && isnothing(probs)
                error("if sampsize given, and popsize not given, then weights or probs must given to calculate popsize")
            end
            for each_strata in keys(data_groupedby_strata)
                if !all(w -> w == first(data_groupedby_strata[each_strata][!, sampsize]), data_groupedby_strata[each_strata][!, sampsize])
                    error("sampsize must be same for all observations within each strata in StratifiedSample")
                end
            end
            # original_sampsize_colname = copy(sampsize)
            sampsize = data[!, sampsize]
            # If sampsize column not provided in constructor call, set it as nrow of strata
        elseif isnothing(sampsize)
            sampsize = transform(groupby(data, strata), nrow => :counts).counts
        end
        # If both `weights` and `probs` given, then `weights` is assumed to be ground truth for probs.
        if !isnothing(weights) && !isnothing(probs)
            probs = 1 ./ weights
            data[!, :probs] = probs
        end
        # `popsize` is either nothing or a Vector{<:Real} by now
        if isnothing(popsize)
            # If popsize not given, fallback to weights, probs and sampsize to estimate `popsize`
            @warn "popsize not given. using weights/probs and sampsize to estimate `popsize` for StratifiedSample"
            # Check that all weights (or probs if weights not given) are equal, as SRS is by definition equi-weighted
            if typeof(probs) <: Vector{<:Real}
                weights = 1 ./ probs
            elseif !(typeof(weights) <: Vector{<:Real})
                error("either weights or probs must be given if `popsize` not given")
            end
            # Estimate population size
            popsize = sampsize .* weights
        elseif typeof(popsize) <: Vector{<:Real} # Still need to check if the provided Column is of <:Real
            # If popsize is given, weights and probs made concordant with popsize and sampsize, regardless of supplied arguments
            weights = popsize ./ sampsize
            probs = 1 ./ weights
        else
            error("something went wrong. Please check validity of inputs.")
        end
        # If sampsize greater than popsize than illogical arguments specified.
        if any(sampsize .> popsize)
            @show sampsize, popsize
            error("population sizes were estimated to be less than sampsize. please check input arguments.")
        end
        # If ignorefpc then set weights to 1 ??
        # TODO: This works under some cases, but should find better way to process ignoring fpc
        if ignorefpc
            @warn "assuming all weights are equal to 1.0"
            weights = ones(nrow(data))
            probs = 1 ./ weights
        end
        ## Set remaining parts of data structure
        # set sampling fraction
        sampfraction = sampsize ./ popsize
        # set fpc
        fpc = ignorefpc ? fill(1, size(data, 1)) : 1 .- (sampsize ./ popsize)
        # add columns for frequency and probability weights to `data`
        data[!, :weights] = weights
        if isnothing(probs)
            probs = 1 ./ data[!, :weights]
        end
        data[!, :probs] = probs
        data[!, :sampsize] = sampsize
        data[!, :popsize] = popsize
        data[!, :fpc] = fpc
        data[!, :sampfraction] = sampfraction
        new(data, strata, ignorefpc)
    end
end

"""
    ClusterSample <: AbstractSurveyDesign

    One stage clusters, Primary Sampling Units (PSU) chosen with SRS. No stratification.
    Assuming every individual is in one and only one cluster, and the subsampling probabilities
    for any given cluster do not depend on which other clusters were sampled. (Lumley pg41, para2)
"""
struct ClusterSample <: AbstractSurveyDesign
    data::AbstractDataFrame
    clusters::Union{Symbol,Nothing}
    sampsize::Union{Nothing,Vector{Real}}
    popsize::Union{Nothing,Vector{Real}}
    sampfraction::Vector{Real}
    fpc::Vector{Real}
    ignorefpc::Bool
    function ClusterSample(data::AbstractDataFrame, strata::Symbol;
        popsize=nothing,
        sampsize=transform(groupby(data, strata), nrow => :counts).counts,
        weights=nothing,
        probs=nothing,
        ignorefpc=false
    )
        if isa(weights, Symbol)
            weights = data[!, weights]
        end
        if isa(probs, Symbol)
            probs = data[!, probs]
        end

        if ignorefpc
            # TODO: change what happens if `ignorepfc == true` or if the user only
            # specifies `data`
            @warn "assuming equal weights"
            weights = ones(nrow(data))
        end

        # set population size if it is not given; `weights` and `sampsize` must be given
        if isnothing(popsize)
            # TODO: add probability weights if `weights` is not `nothing`
            if typeof(probs) <: Vector{<:Real}
                weights = 1 ./ probs
            end
            # estimate population size
            popsize = sampsize .* weights

            if sampsize > popsize
                error("sample size cannot be greater than population size")
            end
        elseif typeof(popsize) <: Vector{<:Real}
            # TODO: change `elseif` condition
            weights = popsize ./ sampsize # expansion estimator
        # TODO: add probability weights
        else
            error("either population size or frequency/probability weights must be specified")
        end
        # set sampling fraction
        sampfraction = sampsize ./ popsize
        # set fpc
        fpc = ignorefpc ? 1 : 1 .- (sampsize ./ popsize)
        # add columns for frequency and probability weights to `data`
        if !isnothing(probs)
            data[!, :probs] = probs
            data[!, :weights] = 1 ./ data[!, :probs]
        else
            data[!, :weights] = weights
            data[!, :probs] = 1 ./ data[!, :weights]
        end
        new(data, strata, sampsize, popsize, sampfraction, fpc, ignorefpc)
    end
end


"""
    SurveyDesign <: AbstractSurveyDesign
    
    Survey design with arbitrary design weights

    clusters: can be passed as `Symbol`, Vector{Symbol}, Vector{Real} or Nothing
    strata: can be passed as `Symbol`, Vector{Symbol}, Vector{Real} or Nothing
    sampsize: can be passed as `Symbol`, Vector{Symbol}, Vector{Real} or Nothing
    popsize: can be passed as `Symbol`, Vector{Symbol}, Vector{Real} or Nothing
"""
struct SurveyDesign <: AbstractSurveyDesign
    data::AbstractDataFrame
    clusters::Union{Symbol,Vector{Symbol},Nothing}
    strata::Union{Symbol,Vector{Symbol},Nothing}
    sampsize::Union{Real,Vector{Real},Nothing}
    popsize::Union{Real,Vector{Real},Nothing}
    sampfraction::Union{Real,Vector{Real}}
    fpc::Union{Real,Vector{Real}}
    ignorefpc::Bool
    # TODO: struct body still work in progress
    function SurveyDesign(data::AbstractDataFrame;
        clusters=nothing,
        strata=nothing,
        popsize=nothing,
        sampsize=nothing,
        weights=nothing,
        probs=nothing,
        ignorefpc=false
    )
        if isnothing(sampsize)
            if isnothing(strata)
                sampsize = nrow(data)
            else
                sampsize = transform(groupby(data, strata), nrow => :counts).counts
            end

        end

        if isa(weights, Symbol)
            weights = data[!, weights]
        end
        if isa(probs, Symbol)
            probs = data[!, probs]
        end
        if isa(popsize, Symbol)
            popsize = data[!, popsize]
        end

        # TODO: Check below, may not be correct for all designs
        if ignorefpc # && (isnothing(popsize) || isnothing(weights) || isnothing(probs))
            @warn "Assuming equal weights"
            weights = ones(nrow(data))
        end

        # TODO: Do the other case where clusters are given
        if isnothing(clusters)
            # set population size if it is not given; `weights` and `sampsize` must be given
            if isnothing(popsize)
                # TODO: add probability weights if `weights` is not `nothing`
                if typeof(probs) <: Vector{<:Real}
                    weights = 1 ./ probs
                end
                # estimate population size
                popsize = sampsize .* weights

                if sampsize > popsize
                    error("sample size cannot be greater than population size")
                end
            elseif typeof(popsize) <: Vector{<:Real}
                # TODO: change `elseif` condition
                weights = popsize ./ sampsize # expansion estimator
            # TODO: add probability weights
            else
                error("either population size or frequency/probability weights must be specified")
            end
            # TODO: for now support SRS within SurveyDesign. Later, just call SimpleRandomSample??
            if typeof(sampsize) <: Real && typeof(popsize) <: Vector{<:Real} # Eg when SRS
                if !all(y -> y == first(popsize), popsize) # SRS by definition is equi-weighted
                    error("Simple Random Sample must be equi-weighted. Different sampling weights detected in vectors")
                end
                popsize = first(popsize) |> Real
            end

            # set sampling fraction
            sampfraction = sampsize ./ popsize
            # set fpc
            fpc = ignorefpc ? 1 : 1 .- (sampsize ./ popsize)
            # add columns for frequency and probability weights to `data`
            if !isnothing(probs)
                data[!, :probs] = probs
                data[!, :weights] = 1 ./ data[!, :probs]
            else
                data[!, :weights] = weights
                data[!, :probs] = 1 ./ data[!, :weights]
            end
            # @show clusters, strata, sampsize,popsize, sampfraction, fpc, ignorefpc
            new(data, clusters, strata, sampsize, popsize, sampfraction, fpc, ignorefpc)
        elseif isa(clusters, Symbol)
            # One Cluster sampling - PSU chosen with SRS,
            print("One stage cluster design with PSU SRS")
        elseif typeof(clusters) <: Vector{Symbol}
            # TODO "Multistage cluster designs"
            print("TODO: Multistage cluster design with PSU SRS")
        end
    end
end