function filter_shocks!(m::AbstractModel, scen::Scenario, system::System)
    # Check applicability of this methodology
    @assert n_instruments(scen) >= n_targets(scen) "Number of instruments must be at least number of targets"

    # Construct data
    df = targets_to_data(m, scen)

    # Set D = 0 and zero out non-instrument shocks
    scen_system = copy(system)

    scen_system.measurement.DD = zeros(size(system[:DD]))

    scen_system.measurement.QQ = copy(system[:QQ])
    for shock in keys(m.exogenous_shocks)
        if !(shock in scen.instrument_names)
            shock_index = m.exogenous_shocks[shock]
            scen_system[:QQ][shock_index, :] = 0
            scen_system[:QQ][:, shock_index] = 0
        end
    end

    # Set initial state and state covariance to 0
    z0 = zeros(n_states_augmented(m))
    P0 = zeros(n_states_augmented(m), n_states_augmented(m))

    # Filter and smooth *deviations from baseline*
    kal = DSGE.filter(m, df, scen_system, z0, P0)
    _, forecastshocks, _ = smooth(m, df, scen_system, kal, draw_states = false,
                                  include_presample = true)

    # Assign shocks to instruments DataFrame
    for shock in keys(m.exogenous_shocks)
        shock_index = m.exogenous_shocks[shock]
        if shock in scen.instrument_names
            scen.instruments[shock] = forecastshocks[shock_index, :]
        else
            @assert all(x -> x == 0, forecastshocks[shock_index, :])
        end
    end

    return forecastshocks
end

function forecast_scenario_draw(m::AbstractModel, scenario_key::Symbol,
                                draw_index::Int, s_T::Vector{Float64})
    # Initialize scenario
    constructor = eval(scenario_key)
    scen = constructor()
    path = scenario_targets_file(m)
    load_scenario_targets!(scen, path, draw_index)

    # Filter shocks
    # TODO: add solving for shocks
    system = compute_system(m)
    forecastshocks = filter_shocks!(m, scen, system)

    # Forecast
    forecaststates, forecastobs, forecastpseudo, _ =
        forecast(m, system, s_T, shocks = forecastshocks)

    # Return output dictionary
    forecast_output = Dict{Symbol, Array{Float64}}()
    forecast_output[:forecaststates] = forecaststates
    forecast_output[:forecastobs]    = forecastobs
    forecast_output[:forecastpseudo] = forecastpseudo
    forecast_output[:forecastshocks] = forecastshocks

    return forecast_output
end