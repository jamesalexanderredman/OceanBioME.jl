# # Simple active particle example
# In this example we will setup a simple 1D column with the [LOBSTER](@ref LOBSTER) biogeochemical model and active particles modelling the growth of sugar kelp. This demonstraits:
# - How to setup OceanBioME's biogeochemical models
# - How to setup light attenuation
# - How to add biologically active particles which interact with the biodeochemical model
# - How to include optional tracer sets (carbonate chemistry and oxygen)
# - How to visulise results

# This is forced by idealised mixing layer depth and surface photosynthetically available radiation (PAR) which are setup first

# ## Install dependencies
# First we will check we have the dependencies installed
# ```julia
# using Pkg
# pkg"add OceanBioME, Oceananigans, Printf, GLMakie"
# ```

# ## Model setup
# We load the packages and choose the default LOBSTER parameter set
using OceanBioME, Oceananigans, Printf
using OceanBioME.SLatissimaModel: SLatissima
using Oceananigans.Units

# ## Surface PAR and turbulent vertical diffusivity based on idealised mixed layer depth 
# Setting up idealised functions for PAR and diffusivity (details here can be ignored but these are typical of the North Atlantic)

@inline PAR⁰(x, y, t) = 60 * (1 - cos((t + 15days) * 2π / 365days))*(1 / (1 + 0.2 * exp(-((mod(t, 365days) - 200days) / 50days) ^ 2))) + 2

@inline H(t, t₀, t₁) = ifelse(t₀ < t < t₁, 1.0, 0.0)

@inline fmld1(t) = H(t, 50days, 365days) * (1 / (1 +exp(-(t - 100days) / (5days)))) * (1 / (1 + exp((t - 330days) / (25days))))

@inline MLD(t) = - (10 + 340 * (1 - fmld1(365days-eps(365days)) * exp(-mod(t, 365days) / 25days) - fmld1(mod(t, 365days))))

@inline κₜ(x, y, z, t) = 1e-2 * (1 + tanh((z - MLD(t))/10)) / 2 + 1e-4

@inline t_function(x, y, z, t) = 2.4 * cos(t * 2π / year + 50day) + 10

# ## Grid and PAR field
# Define the grid and an extra Oceananigans field for the PAR to be stored in
Lx, Ly = 20, 20
grid = RectilinearGrid(size=(1, 1, 50), extent=(Lx, Ly, 200)) 

# ## Kelp Particle setup
@info "Setting up kelp particles"
n = 5 # number of kelp fronds
z₀ = [-21:5:-1;]*1.0 # depth of kelp fronds

particles = SLatissima(; grid, 
                         x = ones(n) * Lx / 2, y = ones(n) * Ly / 2, z = z₀, 
                         A = ones(n) * 30.0, N = ones(n) * 0.01, C =  ones(n) *0.1, 
                         latitude = 57.5,
                         scalefactor = 500.0, 
                         pescribed_temperature = t_function)

# Specify the boundary conditions for DIC and O₂ based on the air-sea CO₂ and O₂ flux
CO₂_flux = GasExchange(; gas = :CO₂, temperature = t_function, salinity = (args...) -> 35)
O₂_flux = GasExchange(; gas = :O₂, temperature = t_function, salinity = (args...) -> 35)

model = NonhydrostaticModel(; grid,
                              closure = ScalarDiffusivity(ν = κₜ, κ = κₜ), 
                              biogeochemistry = LOBSTER(; grid,
                                                          surface_phytosynthetically_active_radiation = PAR⁰,
                                                          carbonates = true,
                                                          variable_redfield = true,
                                                          particles,
                                                          advection_schemes = (sPOM = WENO(grid), bPOM = WENO(grid))),
                              boundary_conditions = (DIC = FieldBoundaryConditions(top = CO₂_flux), ),
                              advection = nothing)

set!(model, P = 0.03, Z = 0.03, NO₃ = 11.0, NH₄ = 0.05, DIC = 2200.0, Alk = 2400.0)

# ## Simulation
# Next we setup the simulation along with some callbacks that:
# - Show the progress of the simulation
# - Store the model and particles output
# - Prevent the tracers from going negative from numerical error (see discussion of this in the [positivity preservation](@ref pos-preservation) implimentation page)

simulation = Simulation(model, Δt=10minutes, stop_time=1year) 

progress_message(sim) = @printf("Iteration: %04d, time: %s, Δt: %s, wall time: %s\n",
                                                        iteration(sim),
                                                        prettytime(sim),
                                                        prettytime(sim.Δt),
                                                        prettytime(sim.run_wall_time))                
simulation.callbacks[:progress] = Callback(progress_message, IterationInterval(100))

filename = "kelp"
simulation.output_writers[:profiles] = JLD2OutputWriter(model, merge(model.tracers, model.auxiliary_fields), filename = "$filename.jld2", schedule = TimeInterval(1day), overwrite_existing=true)


#simulation.output_writers[:particles] = JLD2OutputWriter(model, (; particles), filename = "$(filename)_particles.jld2", schedule = TimeInterval(1day), overwrite_existing = true)

scale_negative_tracers = ScaleNegativeTracers(; model, tracers = (:NO₃, :NH₄, :P, :Z, :sPON, :bPON, :DON))
simulation.callbacks[:neg] = Callback(scale_negative_tracers; callsite = UpdateStateCallsite())

wizard = TimeStepWizard(cfl = 0.2, diffusive_cfl = 0.2, max_change = 2.0, min_change = 0.5, cell_diffusion_timescale = column_diffusion_timescale, cell_advection_timescale = column_advection_timescale)
simulation.callbacks[:wizard] = Callback(wizard, IterationInterval(1))

# ## Run!
# Finally we run the simulation
#=run!(simulation)

# Now we can visulise the results with some post processing to diagnose the air-sea CO₂ flux - hopefully this looks different to the example without kelp!

P = FieldTimeSeries("$filename.jld2", "P")
NO₃ = FieldTimeSeries("$filename.jld2", "NO₃")
Z = FieldTimeSeries("$filename.jld2", "Z")
sPON = FieldTimeSeries("$filename.jld2", "sPON") 
bPON = FieldTimeSeries("$filename.jld2", "bPON")
DIC = FieldTimeSeries("$filename.jld2", "DIC")
sPOC = FieldTimeSeries("$filename.jld2", "sPOC")
bPOC = FieldTimeSeries("$filename.jld2", "bPOC")
Alk = FieldTimeSeries("$filename.jld2", "Alk")

x, y, z = nodes(P)
times = P.times

air_sea_CO₂_flux = zeros(size(P)[4])
carbon_export = zeros(size(P)[4])
for (i, t) in enumerate(times)
    air_sea_CO₂_flux[i] = CO₂_flux.condition.parameters(0.0, 0.0, t, DIC[1, 1, 50, i], Alk[1, 1, 50, i], t_function(1, 1, 0, t), 35)
    carbon_export[i] = (200 / 50) * (sPOC[1, 1, end-20, i] * model.biogeochemistry.sinking_velocities.sPOM.w[1, 1, end - 20] .+ bPOC[1, 1, end-20, i] * model.biogeochemistry.sinking_velocities.bPOM.w[1, 1, end - 20])
end

using CairoMakie
f=Figure(backgroundcolor=RGBf(1, 1, 1), fontsize=30, resolution = (1920, 1050))

axP = Axis(f[1, 1:2], ylabel="z (m)", xlabel="Time (days)", title="Phytoplankton concentration (mmol N/m³)")
hmP = heatmap!(times./days, float.(z[end-23:end]), float.(P[1, 1, end-23:end, 1:end])', interpolate=true, colormap=:batlow)
cbP = Colorbar(f[1, 3], hmP)

axNO₃ = Axis(f[1, 4:5], ylabel="z (m)", xlabel="Time (days)", title="Nitrate concentration (mmol N/m³)")
hmNO₃ = heatmap!(times./days, float.(z[end-23:end]), float.(NO₃[1, 1, end-23:end, 1:end])', interpolate=true, colormap=:batlow)
cbNO₃ = Colorbar(f[1, 6], hmNO₃)

axZ = Axis(f[2, 1:2], ylabel="z (m)", xlabel="Time (days)", title="Zooplankton concentration (mmol N/m³)")
hmZ = heatmap!(times./days, float.(z[end-23:end]), float.(Z[1, 1, end-23:end, 1:end])', interpolate=true, colormap=:batlow)
cbZ = Colorbar(f[2, 3], hmZ)

axD = Axis(f[2, 4:5], ylabel="z (m)", xlabel="Time (days)", title="Detritus concentration (mmol C/m³)")
hmD = heatmap!(times./days, float.(z[end-23:end]), float.(sPOC[1, 1, end-23:end, 1:end])' .+ float.(bPOC[1, 1, end-23:end, 1:end])', interpolate=true, colormap=:batlow)
cbD = Colorbar(f[2, 6], hmD)

axfDIC = Axis(f[3, 1:4], xlabel="Time (days)", title="Air-sea CO₂ flux and Sinking", ylabel="Flux (kgCO₂/m²/year)")
hmfDIC = lines!(times ./ days, air_sea_CO₂_flux .* (12 + 16 * 2) .* year /(1000 * 1000), label="Air-sea flux")
hmfExp = lines!(times ./ days, carbon_export .* (12 + 16 * 2) .* year / (1000 * 1000), label="Sinking export")

f[3, 5] = Legend(f, axfDIC, "", framevisible = false)

save("$(filename).png", f)

# ![Results-bgc](kelp.png)

# We can also have a look at how the kelp particles evolve
using JLD2

file_profiles = jldopen("$(filename)_particles.jld2")

iterations = parse.(Int, keys(file_profiles["timeseries/t"]))
tracers=keys(file_profiles["timeseries/particles/$(iterations[1])"])

times = [file_profiles["timeseries/t/$iter"] for iter in iterations]

results = zeros(length(tracers), length(getproperty(file_profiles["timeseries/particles/$(iterations[1])"], tracers[1])), length(iterations))
times = zeros(length(iterations))
for (i, iter) in enumerate(iterations)
    times[i] = file_profiles["timeseries/t/$iter"]
    for (j, tracer) in enumerate(tracers)
        results[j, :, i] .= getproperty(file_profiles["timeseries/particles/$iter"], tracer)
    end
end

xs, ys = times/(1day), results[3,:,1]

f = Figure(backgroundcolor = RGBf(1, 1, 1), resolution = (1920, 1050))
gInput = f[1, 1] = GridLayout()
gProperties = f[1, 2] = GridLayout()
gOutput = f[1, 3] = GridLayout()

ax1, hm1 = heatmap(gInput[1, 1], xs, ys, results[18,:,:]')
ax1.title = "NO₃"
ax1.xticklabelsvisible= false
cb1 = Colorbar(gInput[1, 1:2], hm1, label = "mmol N/m³")

ax2, hm2 = heatmap(gInput[2, 1], xs, ys, results[19,:,:]')
ax2.title = "NH₄"
ax2.ylabel = "depth (m)"
ax2.xticklabelsvisible= false
cb2 = Colorbar(gInput[2, 1:2], hm2, label = "mmol N/m³")

ax3, hm3 = heatmap(gInput[3, 1], xs, ys, results[20,:,:]')
ax3.title = "PAR"
ax3.xlabel = "time (day)"
cb3 = Colorbar(gInput[3, 1:2], hm3, label = "einstein/m²/day")

ax1, hm1 = heatmap(gProperties[1, 1], xs, ys, results[7,:,:]')
ax1.title = "Area"
ax1.xticklabelsvisible= false
cb1 = Colorbar(gProperties[1, 1:2], hm1, label = "dm²")

ax2, hm2 = heatmap(gProperties[2, 1], xs, ys, ((results[8,:,:] .+ SLatissima.defaults.N_struct) .* SLatissima.defaults.K_A .* results[7, :, :])')
ax2.title = "Total Nitrogen (structural + reserve)"
ax2.ylabel = "depth (m)"
ax2.xticklabelsvisible= false
cb2 = Colorbar(gProperties[2, 1:2], hm2, label = "gN/frond")

ax3, hm3 = heatmap(gProperties[3, 1], xs, ys, ((results[9,:,:] .+ SLatissima.defaults.C_struct) .* SLatissima.defaults.K_A .* results[7, :, :])')
ax3.title = "Total Carbon (structural + reserve)"
ax3.xlabel = "time (day)"
cb3 = Colorbar(gProperties[3, 1:2], hm3, label = "gC/frond")

ax1, hm1 = heatmap(gOutput[1, 1], xs, ys, -results[10,:,:]')
ax1.title = "NO₃ uptake"
cb1 = Colorbar(gOutput[1, 1:2], hm1, label = "mmol N/s")
ax1.xticklabelsvisible= false

ax2, hm2 = heatmap(gOutput[2, 1], xs, ys, -results[11,:,:]')
ax2.title = "NH₄ uptake"
ax2.xticklabelsvisible= false
cb2 = Colorbar(gOutput[2, 1:2], hm2, label = "mmol N/s")

ax3, hm3 = heatmap(gOutput[3, 1], xs, ys, -results[12,:,:]')
ax3.title = "Primary production (photosynthesis - respiration)"
ax3.xticklabelsvisible= false
ax3.ylabel = "depth (m)"
cb3 = Colorbar(gOutput[3, 1:2], hm3, label = "mmol C/s")

ax4, hm4 = heatmap(gOutput[4, 1], xs, ys, results[15,:,:]')
ax4.title = "Exudation (DOC output)"
ax4.xticklabelsvisible= false
cb4 = Colorbar(gOutput[4, 1:2], hm4, label = "mmol C/s")

ax5, hm5 = heatmap(gOutput[5, 1], xs, ys, results[17,:,:]')
ax5.title = "Frond errosion (POC output)"
ax5.xlabel = "time (day)"
cb5 = Colorbar(gOutput[5, 1:2], hm5, label = "mmol C/s")
save("$(filename)_particles.png", f)

# ![Results](kelp_particles.png)=#