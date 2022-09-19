@inline Cₚᵣₒ(P, Chlᴾ, PARᴾ, L_day, α, μₚ, Lₗᵢₘᴾ)=1-exp(-α*(Chlᴾ/P)*PARᴾ/(L_day*μₚ*Lₗᵢₘᴾ))

@inline f₁(L_day) = 1.5*L_day/(0.5+L_day)#eq 3a
@inline t_dark(zₘₓₗ, zₑᵤ) = max(0, zₘₓₗ-zₑᵤ)^2/86400#eq 3b,c
@inline f₂(zₘₓₗ, zₑᵤ, t_dark_lim) = 1 - t_dark(zₘₓₗ, zₑᵤ)/(t_dark(zₘₓₗ, zₑᵤ)+t_dark_lim) #eq 3d

@inline L_NO₃(NO₃, NH₄, K_NO₃, K_NH₄) = K_NO₃*NH₄/(K_NO₃*K_NH₄+K_NH₄*NO₃+K_NO₃*NH₄) #eq 6e
@inline L_NH₄(NO₃, NH₄, K_NO₃, K_NH₄) = K_NH₄*NO₃/(K_NO₃*K_NH₄+K_NH₄*NO₃+K_NO₃*NH₄) #eq 6d
#@inline Lₙ(NO₃, NH₄, K_NO₃, K_NH₄) = L_NO₃(NO₃, NH₄, K_NO₃, K_NH₄) + L_NH₄(NO₃, NH₄, K_NO₃, K_NH₄)
@inline L_mondo(C, K) = C/(C+K) #eq 6b

@inline L_Fe(P, Chlᴾ, Feᴾ, θᶠᵉₒₚₜ, Lₙᴾ, Lₙₒ₃ᴾ) = min(1, max(0, ((Feᴾ/P) - θᶠᵉₘᵢₙ(P, Chlᴾ, Lₙᴾ, Lₙₒ₃ᴾ))/θᶠᵉₒₚₜ)) #eq 6f
@inline θᶠᵉₘᵢₙ(P, Chlᴾ, Lₙᴾ, Lₙₒ₃ᴾ) = 0.0016*Chlᴾ/(55.85*P) + 1.21e-5*14*Lₙᴾ/(55.85*7.625)*1.5+1.15*14*L_NO₃ᴾ/(55.85*7.625) #eq 20 -> Lₙ could be meant to be L_NH₄?

@inline Lₗᵢₘ(P, Chlᴾ, Feᴾ, NO₃, NH₄, PO₄, Fe, ) = min(Lₚₒ₄(PO₄, P, I, params), 
                                                                            Lₙ(NO₃, NH₄, I, params),
                                                                            L_Fe(p, Chlᴾ, Feᴾ, NO₃, NH₄, I, params),
                                                                            I==:D ? params.Kₛᵢᴰᵐⁱⁿ + 7*params.Si̅^2/(params.Kₛᵢ^2+params.Si̅^2) : Inf)

@inline K(P, Kᵐⁱⁿ, Sᵣₐₜ, Pₘₐₓ) = Kᵐⁱⁿ*(P₁(P, Pₘₐₓ)+Sᵣₐₜ*P₂(P, Pₘₐₓ))/(P₁(P, Pₘₐₓ)+P₂(P, Pₘₐₓ))
@inline P₁(P, Pₘₐₓ) = min(P, params.Pₘₐₓ[I])
@inline P₂(P, Pₘₐₓ) = min(0, P - params.Pₘₐₓ[I])

#perhaps should add an auxiliary forcing before to compute all of the reused values such as z_food_total, F_lim^Z etc.? which otherwise get computed 4 times minimum
#think the trade off here varies for CPU vs GPU where we might want to not recompute them on CPU but we may want to store less in memory on GPU
function P_forcing(x, y, z, t, P, D, Chlᴾ, Chlᴰ, Feᴾ, Feᴰ, Siᴰ, Z, M, DOC, POC, GOC, Feᴾᴼ, Feᴳᴼ, Siᴾᴼ, Siᴳᴼ, NO₃, NH₄, PO₄, Fe, Si, CaCO₃, DIC, O₂, PARᴾ, PARᴰ, T, zₘₓₗ, zₑᵤ, ϕ, params)
    #growth
    L_day = params.L_day(t)

    Lₚₒ₄ᴾ = L_mondo(PO₄, K(P, params.Kᵐⁱⁿ.PO₄.P, params.Sᵣₐₜ.P, params.Pₘₐₓ.P))
    L_NO₃ᴾ = L_NO₃ᴾ(NO₃, NH₄, params.K_NO₃.P, params.K_NH₄.P)
    Lₙᴾ = L_NO₃ᴾ + L_NH₄(NO₃, NH₄, params.K_NO₃.P, params.K_NH₄.P) #eq 6c
    L_Feᴾ = L_Fe(P, Chlᴾ, Feᴾ, params.θᶠᵉₒₚₜ.P, Lₙᴾ, Lₙₒ₃ᴾ)
    Lₗᵢₘᴾ = min(Lₚₒ₄ᴾ, Lₙᴾ, L_Feᴾ)

    μₚ = (μₘₐₓ⁰*params.b.P^T)
    μᴾ = μₚ*f₁(L_day)*f₂(zₘₓₗ, zₑᵤ, params.t_dark.P)*Cₚᵣₒ(P, Chlᴾ, PARᴾ, L_day, params.α.P, μₚ, Lₗᵢₘᴾ)*Lₗᵢₘᴾ #eq2a

    #shear
    sh = zₘₓₗ<z ? params.shₘₓₗ : params.shₛᵤ

    #grazing
    z_food_total = food_total(params.p.Z, (; P, D, POC)) #could store this as an auxiliary field that is forced so it doesn't need to be computed for P, D, POC and Z
    m_food_total = food_total(params.p.M, (; P, D, POC, Z)) #may be inconcenient/impossible to get it to calculate it first though, could make this descrete 

    gᶻₚ = g(params.p.Z.P*(P-params.Jₜₕᵣ.Z.P), params.gₘₐₓ⁰.Z*params.b.Z^T, Fₗᵢₘ(params.p.Z, params.Jₜₕᵣ.Z, params.Fₜₕᵣ.Z, (; P, D, POC)), F(params.p.Z, params.Jₜₕᵣ.Z, (; P, D, POC)), params.K_G.Z, z_food_total)
    gᴹₚ = g(params.p.M.P*(P-params.Jₜₕᵣ.M.P), params.gₘₐₓ⁰.M*params.b.M^T, Fₗᵢₘ(params.p.M, params.Jₜₕᵣ.M, params.Fₜₕᵣ.M, (; P, D, POC, Z)), F(params.p.M, params.Jₜₕᵣ.M, (; P, D, POC, Z)), params.K_G.M, m_food_total)

    return (1 - params.δ.P)*μᴾ*P - params.m.P*P^2/(params.Kₘ+P) - sh*params.wᴾ*P^2 - gᶻₚ*Z - gᴹₚ*M#eq 1
end

function D_forcing(x, y, z, t, P, D, Chlᴾ, Chlᴰ, Feᴾ, Feᴰ, Siᴰ, Z, M, DOC, POC, GOC, Feᴾᴼ, Feᴳᴼ, Siᴾᴼ, Siᴳᴼ, NO₃, NH₄, PO₄, Fe, Si, CaCO₃, DIC, O₂, PARᴾ, PARᴰ, T, zₘₓₗ, zₑᵤ, ϕ, params)
    #growth
    L_day = params.L_day(t)

    Lₚₒ₄ᴰ = L_mondo(PO₄, K(D, params.Kᵐⁱⁿ.PO₄.D, params.Sᵣₐₜ.D, params.Pₘₐₓ.D))
    L_NO₃ᴰ = L_NO₃ᴾ(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D)
    Lₙᴰ = L_NO₃ᴰ + L_NH₄(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D) #eq 6c
    L_Feᴰ = L_Fe(P, Chlᴰ, Feᴰ, params.θᶠᵉₒₚₜ.D, Lₙᴰ, Lₙₒ₃ᴰ)
    Lₛᵢᴰ = L_mondo(Si, params.Kₛᵢᴰᵐⁱⁿ + 7*params.Si̅^2/(params.Kₛᵢ^2+params.Si̅^2)) # eq 11b, 12. Need a callback that records Sī

    Lₗᵢₘᴰ = min(Lₚₒ₄ᴰ, Lₙᴰ, L_Feᴰ, Lₛᵢᴰ)

    μ_d = (μₘₐₓ⁰*params.b.D^T)
    μᴰ = μ_d*f₁(L_day)*f₂(zₘₓₗ, zₑᵤ, params.t_dark.D)*Cₚᵣₒ(D, Chlᴰ, PARᴰ, L_day, params.α.D, μ_d, Lₗᵢₘᴰ)*Lₗᵢₘᴰ #eq2a

    #shear
    sh = zₘₓₗ<z ? params.shₘₓₗ : params.shₛᵤ 

    #grazing
    z_food_total = food_total(params.p.Z, (; P, D, POC)) #could store this as an auxiliary field that is forced so it doesn't need to be computed for P, D, POC and Z
    m_food_total = food_total(params.p.M, (; P, D, POC, Z)) #may be inconcenient/impossible to get it to calculate it first though, could make this descrete 

    gᶻ_D = g(params.p.Z.D*(D-params.Jₜₕᵣ.Z.D), params.gₘₐₓ⁰.Z*params.b.Z^T, Fₗᵢₘ(params.p.Z, params.Jₜₕᵣ.Z, params.Fₜₕᵣ.Z, (; P, D, POC)), F(params.p.Z, params.Jₜₕᵣ.Z, (; P, D, POC)), params.K_G.Z, z_food_total)
    gᴹ_D = g(params.p.M.D*(D-params.Jₜₕᵣ.M.D), params.gₘₐₓ⁰.M*params.b.M^T, Fₗᵢₘ(params.p.M, params.Jₜₕᵣ.M, params.Fₜₕᵣ.M, (; P, D, POC, Z)), F(params.p.M, params.Jₜₕᵣ.M, (; P, D, POC, Z)), params.K_G.M, m_food_total)

    return (1 - params.δ.D)*μᴰ*D - params.m.D*D^2/(params.Kₘ+D) - sh*(params.wᴾ+ params.wₘₐₓᴰ*(1-Lₗᵢₘᴰ))*D^2 - gᶻ_D*Z - gᴹ_D*M#eq 9
end

function Chlᴾ_forcing(x, y, z, t, P, D, Chlᴾ, Chlᴰ, Feᴾ, Feᴰ, Siᴰ, Z, M, DOC, POC, GOC, Feᴾᴼ, Feᴳᴼ, Siᴾᴼ, Siᴳᴼ, NO₃, NH₄, PO₄, Fe, Si, CaCO₃, DIC, O₂, PARᴾ, PARᴰ, T, zₘₓₗ, zₑᵤ, ϕ, params)
    #growth
    L_day = params.L_day(t)

    Lₚₒ₄ᴾ = L_mondo(PO₄, K(P, params.Kᵐⁱⁿ.PO₄.P, params.Sᵣₐₜ.P, params.Pₘₐₓ.P))
    L_NO₃ᴾ = L_NO₃ᴾ(NO₃, NH₄, params.K_NO₃.P, params.K_NH₄.P)
    Lₙᴾ = L_NO₃ᴾ + L_NH₄(NO₃, NH₄, params.K_NO₃.P, params.K_NH₄.P) #eq 6c
    L_Feᴾ = L_Fe(P, Chlᴾ, Feᴾ, params.θᶠᵉₒₚₜ.P, Lₙᴾ, Lₙₒ₃ᴾ)

    μₚ = (μₘₐₓ⁰*params.b.P^T)
    μᴾ = μₚ*f₁(L_day)*f₂(zₘₓₗ, zₑᵤ, params.t_dark.P)*Cₚᵣₒ(P, Chlᴾ, PARᴾ, L_day, params.α.P, params.μᵣₑ, params.bᵣₑₛₚ)*min(Lₚₒ₄ᴾ, Lₙᴾ, L_Feᴾ) #eq2a

    μ̌ᴾ = (μᴾ/f₁(L_day))
    ρᶜʰˡᵖ = 144*μ̌ᴾ*P/(params.α.P*Chlᴾ*PARᴾ/L_day)
    #shear
    sh = zₘₓₗ<z ? params.shₘₓₗ : params.shₛᵤ

    #grazing
    z_food_total = food_total(params.p.Z, (; P, D, POC)) #could store this as an auxiliary field that is forced so it doesn't need to be computed for P, D, POC and Z
    m_food_total = food_total(params.p.M, (; P, D, POC, Z)) #may be inconcenient/impossible to get it to calculate it first though, could make this descrete 

    gᶻₚ = g(params.p.Z.P*(P-params.Jₜₕᵣ.Z.P), params.gₘₐₓ⁰.Z*params.b.Z^T, Fₗᵢₘ(params.p.Z, params.Jₜₕᵣ.Z, params.Fₜₕᵣ.Z, (; P, D, POC)), F(params.p.Z, params.Jₜₕᵣ.Z, (; P, D, POC)), params.K_G.Z, z_food_total)
    gᴹₚ = g(params.p.M.P*(P-params.Jₜₕᵣ.M.P), params.gₘₐₓ⁰.M*params.b.M^T, Fₗᵢₘ(params.p.M, params.Jₜₕᵣ.M, params.Fₜₕᵣ.M, (; P, D, POC, Z)), F(params.p.M, params.Jₜₕᵣ.M, (; P, D, POC, Z)), params.K_G.M, m_food_total)

    return (1 - params.δ.P)*(12*params.θᶜʰˡₘᵢₙ + (θᶜʰˡₘₐₓ.P-θᶜʰˡₘᵢₙ)*ρᶜʰˡᴾ)*μᴾ*P - params.m.P*P*Chlᴾ/(params.Kₘ+P) - sh*params.wᴾ*P*Chlᴾ - (Chlᴾ/P)*(gᶻₚ*Z + gᴹₚ*M)#eq 14
end

function Chlᴰ_forcing(x, y, z, t, P, D, Chlᴾ, Chlᴰ, Feᴾ, Feᴰ, Siᴰ, Z, M, DOC, POC, GOC, Feᴾᴼ, Feᴳᴼ, Siᴾᴼ, Siᴳᴼ, NO₃, NH₄, PO₄, Fe, Si, CaCO₃, DIC, O₂, PARᴾ, PARᴰ, T, zₘₓₗ, zₑᵤ, ϕ, params)
    #growth
    L_day = params.L_day(t)

    Lₚₒ₄ᴰ = L_mondo(PO₄, K(D, params.Kᵐⁱⁿ.PO₄.D, params.Sᵣₐₜ.D, params.Pₘₐₓ.D))
    L_NO₃ᴰ = L_NO₃ᴾ(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D)
    Lₙᴰ = L_NO₃ᴰ + L_NH₄(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D) #eq 6c
    L_Feᴰ = L_Fe(P, Chlᴰ, Feᴰ, params.θᶠᵉₒₚₜ.D, Lₙᴰ, Lₙₒ₃ᴰ)
    Lₛᵢᴰ = L_mondo(Si, params.Kₛᵢᴰᵐⁱⁿ + 7*params.Si̅^2/(params.Kₛᵢ^2+params.Si̅^2)) # eq 11b, 12. Need a callback that records Sī

    Lₗᵢₘᴰ = min(Lₚₒ₄ᴰ, Lₙᴰ, L_Feᴰ, Lₛᵢᴰ)

    μ_d = (μₘₐₓ⁰*params.b.D^T)
    μᴰ = μ_d*f₁(L_day)*f₂(zₘₓₗ, zₑᵤ, params.t_dark.D)*Cₚᵣₒ(D, Chlᴰ, PARᴰ, L_day, params.α.D, μ_d, Lₗᵢₘᴰ)*Lₗᵢₘᴰ #eq2a

    μ̌ᴰ = (μᴰ/f₁(L_day)) #eq 15a
    ρᶜʰˡᴰ = 144*μ̌ᴰ*D/(params.α.D*Chlᴰ*PARᴰ/L_day) #eq 15a
    #shear
    sh = zₘₓₗ<z ? params.shₘₓₗ : params.shₛᵤ 

    #grazing
    z_food_total = food_total(params.p.Z, (; P, D, POC)) #could store this as an auxiliary field that is forced so it doesn't need to be computed for P, D, POC and Z
    m_food_total = food_total(params.p.M, (; P, D, POC, Z)) #may be inconcenient/impossible to get it to calculate it first though, could make this descrete 

    gᶻ_D = g(params.p.Z.D*(D-params.Jₜₕᵣ.Z.D), params.gₘₐₓ⁰.Z*params.b.Z^T, Fₗᵢₘ(params.p.Z, params.Jₜₕᵣ.Z, params.Fₜₕᵣ.Z, (; P, D, POC)), F(params.p.Z, params.Jₜₕᵣ.Z, (; P, D, POC)), params.K_G.Z, z_food_total)
    gᴹ_D = g(params.p.M.D*(D-params.Jₜₕᵣ.M.D), params.gₘₐₓ⁰.M*params.b.M^T, Fₗᵢₘ(params.p.M, params.Jₜₕᵣ.M, params.Fₜₕᵣ.M, (; P, D, POC, Z)), F(params.p.M, params.Jₜₕᵣ.M, (; P, D, POC, Z)), params.K_G.M, m_food_total)

    return (1 - params.δ.D)*(12*params.θᶜʰˡₘᵢₙ + (θᶜʰˡₘₐₓ.P-θᶜʰˡₘᵢₙ)*ρᶜʰˡᴾ)*μᴰ*D - params.m.D*D*Chlᴰ/(params.Kₘ+D) - sh*(params.wᴾ+ params.wₘₐₓᴰ*(1-Lₗᵢₘᴰ))*D*Chlᴰ - (Chlᴰ/D)*(gᶻ_D*Z + gᴹ_D*M)#eq 14
end

function Feᴾ_forcing(x, y, z, t, P, D, Chlᴾ, Chlᴰ, Feᴾ, Feᴰ, Siᴰ, Z, M, DOC, POC, GOC, Feᴾᴼ, Feᴳᴼ, Siᴾᴼ, Siᴳᴼ, NO₃, NH₄, PO₄, Fe, Si, CaCO₃, DIC, O₂, PARᴾ, PARᴰ, T, zₘₓₗ, zₑᵤ, ϕ, params)
    #growth
    L_day = params.L_day(t)
    μₚ = (μₘₐₓ⁰*params.b.P^T)

    P₂ = max(0, P - params.Pₘₐₓ)
    P₁ = P - P₂
    K_Feᶠᵉᴾ = params.K_Feᵐⁱⁿ.P*(P₁ + params.Sᵣₐₜ.P*P₂)/(P₁ + P₂)

    L_NO₃ᴾ = L_NO₃ᴾ(NO₃, NH₄, params.K_NO₃.P, params.K_NH₄.P)
    Lₙᴾ = L_NO₃ᴾ + L_NH₄(NO₃, NH₄, params.K_NO₃.P, params.K_NH₄.P) #eq 6c
    L_Feᴾ = L_Fe(P, Chlᴾ, Feᴾ, params.θᶠᵉₒₚₜ.P, Lₙᴾ, Lₙₒ₃ᴾ)

    bFe = Fe #with the complex chemsitry implimented this would not just be Fe
    μᶠᵉᵖ = params.θᶠᵉₘₐₓ.P*L_mondo(bFe, K_Feᶠᵉᴾ)*((4-4.5*L_Feᴾ)/(L_Feᴾ+0.5))*((1 - (Feᴾ/P)/params.θᶠᵉₘₐₓ.P)/(1.05 - (Feᴾ/P)/params.θᶠᵉₘₐₓ.P))*μₚ

    #Not really sure why it defined θᶠᵉₘᵢₙ, perhaps a typo or used somewhere else
   
    #shear
    sh = zₘₓₗ<z ? params.shₘₓₗ : params.shₛᵤ

    #grazing
    z_food_total = food_total(params.p.Z, (; P, D, POC)) #could store this as an auxiliary field that is forced so it doesn't need to be computed for P, D, POC and Z
    m_food_total = food_total(params.p.M, (; P, D, POC, Z)) #may be inconcenient/impossible to get it to calculate it first though, could make this descrete 

    gᶻₚ = g(params.p.Z.P*(P-params.Jₜₕᵣ.Z.P), params.gₘₐₓ⁰.Z*params.b.Z^T, Fₗᵢₘ(params.p.Z, params.Jₜₕᵣ.Z, params.Fₜₕᵣ.Z, (; P, D, POC)), F(params.p.Z, params.Jₜₕᵣ.Z, (; P, D, POC)), params.K_G.Z, z_food_total)
    gᴹₚ = g(params.p.M.P*(P-params.Jₜₕᵣ.M.P), params.gₘₐₓ⁰.M*params.b.M^T, Fₗᵢₘ(params.p.M, params.Jₜₕᵣ.M, params.Fₜₕᵣ.M, (; P, D, POC, Z)), F(params.p.M, params.Jₜₕᵣ.M, (; P, D, POC, Z)), params.K_G.M, m_food_total)

    return (1 - params.δ.P)*μᶠᵉᴾ*P - params.m.P*P*Feᴾ/(params.Kₘ+P) - sh*params.wᴾ*P*Feᴾ - (Feᴾ/P)*(gᶻₚ*Z + gᴹₚ*M)#eq 16
end

function Feᴰ_forcing(x, y, z, t, P, D, Chlᴾ, Chlᴰ, Feᴾ, Feᴰ, Siᴰ, Z, M, DOC, POC, GOC, Feᴾᴼ, Feᴳᴼ, Siᴾᴼ, Siᴳᴼ, NO₃, NH₄, PO₄, Fe, Si, CaCO₃, DIC, O₂, PARᴾ, PARᴰ, T, zₘₓₗ, zₑᵤ, ϕ, params)
    #growth
    L_day = params.L_day(t)
    μ_D = (μₘₐₓ⁰*params.b.D^T)

    D₂ = max(0, D - params.Dₘₐₓ)
    D₁ = D - D₂
    K_Feᶠᵉᴰ = params.K_Feᵐⁱⁿ.D*(D₁ + params.Sᵣₐₜ.D*D₂)/(D₁ + D₂)

    Lₚₒ₄ᴰ = L_mondo(PO₄, K(D, params.Kᵐⁱⁿ.PO₄.D, params.Sᵣₐₜ.D, params.Pₘₐₓ.D))
    L_NO₃ᴰ = L_NO₃ᴾ(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D)
    Lₙᴰ = L_NO₃ᴰ + L_NH₄(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D) #eq 6c
    L_Feᴰ = L_Fe(P, Chlᴰ, Feᴰ, params.θᶠᵉₒₚₜ.D, Lₙᴰ, Lₙₒ₃ᴰ)
    Lₛᵢᴰ = L_mondo(Si, params.Kₛᵢᴰᵐⁱⁿ + 7*params.Si̅^2/(params.Kₛᵢ^2+params.Si̅^2)) # eq 11b, 12. Need a callback that records Sī

    Lₗᵢₘᴰ = min(Lₚₒ₄ᴰ, Lₙᴰ, L_Feᴰ, Lₛᵢᴰ)

    bFe = Fe #with the complex chemsitry implimented this would not just be Fe
    μᶠᵉᴰ = params.θᶠᵉₘₐₓ.D*L_mondo(bFe, K_Feᶠᵉᴰ)*((4-4.5*L_Feᴰ)/(L_Feᴰ+0.5))*((1 - (Feᴰ/D)/params.θᶠᵉₘₐₓ.D)/(1.05 - (Feᴰ/D)/params.θᶠᵉₘₐₓ.D))*μ_D
    
    #shear
    sh = zₘₓₗ<z ? params.shₘₓₗ : params.shₛᵤ 

    #grazing
    z_food_total = food_total(params.p.Z, (; P, D, POC)) #could store this as an auxiliary field that is forced so it doesn't need to be computed for P, D, POC and Z
    m_food_total = food_total(params.p.M, (; P, D, POC, Z)) #may be inconcenient/impossible to get it to calculate it first though, could make this descrete 

    gᶻ_D = g(params.p.Z.D*(D-params.Jₜₕᵣ.Z.D), params.gₘₐₓ⁰.Z*params.b.Z^T, Fₗᵢₘ(params.p.Z, params.Jₜₕᵣ.Z, params.Fₜₕᵣ.Z, (; P, D, POC)), F(params.p.Z, params.Jₜₕᵣ.Z, (; P, D, POC)), params.K_G.Z, z_food_total)
    gᴹ_D = g(params.p.M.D*(D-params.Jₜₕᵣ.M.D), params.gₘₐₓ⁰.M*params.b.M^T, Fₗᵢₘ(params.p.M, params.Jₜₕᵣ.M, params.Fₜₕᵣ.M, (; P, D, POC, Z)), F(params.p.M, params.Jₜₕᵣ.M, (; P, D, POC, Z)), params.K_G.M, m_food_total)

    return (1 - params.δ.D)*μᶠᵉᴰ*D - params.m.D*D*Feᴰ/(params.Kₘ+D) - sh*(params.wᴾ+ params.wₘₐₓᴰ*(1-Lₗᵢₘᴰ))*D*Feᴰ - (Feᴰ/D)*(gᶻ_D*Z + gᴹ_D*M)#eq 17
end

function Siᴰ_forcing(x, y, z, t, P, D, Chlᴾ, Chlᴰ, Feᴾ, Feᴰ, Siᴰ, Z, M, DOC, POC, GOC, Feᴾᴼ, Feᴳᴼ, Siᴾᴼ, Siᴳᴼ, NO₃, NH₄, PO₄, Fe, Si, CaCO₃, DIC, O₂, PARᴾ, PARᴰ, T, zₘₓₗ, zₑᵤ, ϕ, params)
    #growth
    L_day = params.L_day(t)

    Lₚₒ₄ᴰ = L_mondo(PO₄, K(D, params.Kᵐⁱⁿ.PO₄.D, params.Sᵣₐₜ.D, params.Pₘₐₓ.D))
    L_NO₃ᴰ = L_NO₃ᴾ(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D)
    Lₙᴰ = L_NO₃ᴰ + L_NH₄(NO₃, NH₄, params.K_NO₃.D, params.K_NH₄.D) #eq 6c
    L_Feᴰ = L_Fe(P, Chlᴰ, Feᴰ, params.θᶠᵉₒₚₜ.D, Lₙᴰ, Lₙₒ₃ᴰ)
    Lₛᵢᴰ = L_mondo(Si, params.Kₛᵢᴰᵐⁱⁿ + 7*params.Si̅^2/(params.Kₛᵢ^2+params.Si̅^2)) # eq 11b, 12. Need a callback that records Sī

    Lₗᵢₘᴰ = min(Lₚₒ₄ᴰ, Lₙᴰ, L_Feᴰ, Lₛᵢᴰ)

    μ_d = (μₘₐₓ⁰*params.b.D^T)
    μᴰ = μ_d*f₁(L_day)*f₂(zₘₓₗ, zₑᵤ, params.t_dark.D)*Cₚᵣₒ(D, Chlᴰ, PARᴰ, L_day, params.α.D, μ_d, Lₗᵢₘᴰ)*Lₗᵢₘᴰ #eq2a

    #optimum quota
    Lₗₘ₁ˢⁱᴰ = L_mondo(Si, params.Kₛᵢ¹) #eq 23c
    Lₗᵢₘ₂ˢⁱᴰ = θ<0 ?  L_mond(Si^3, params.Kₛᵢ²^3) : 0 #eq 23d
    Fₗᵢₘ₁ˢⁱᴰ = min(μᴰ/(μ_D*Lₗᵢₘᴰ), Lₚₒ₄ᴰ, Lₙᴰ, L_Feᴰ) #eq 23a
    Fₗᵢₘ₂ˢⁱᴰ = min(1, 2.2*max(0, Lₗₘ₁ˢⁱᴰ - 0.5)) #eq 23b

    θₒₚₜˢⁱᴰ = params.θˢⁱᴰₘ*Lₗᵢₘ₁ˢⁱᴰ*min(5.4, (4.4*exp(-4.23*Fₗᵢₘ₁ˢⁱᴰ)*Fₗᵢₘ₂ˢⁱᴰ+1)*(1+2*Lₗᵢₘ₂ˢⁱᴰ))#eq 22
    
    #shear
    sh = zₘₓₗ<z ? params.shₘₓₗ : params.shₛᵤ 

    #grazing
    z_food_total = food_total(params.p.Z, (; P, D, POC)) #could store this as an auxiliary field that is forced so it doesn't need to be computed for P, D, POC and Z
    m_food_total = food_total(params.p.M, (; P, D, POC, Z)) #may be inconcenient/impossible to get it to calculate it first though, could make this descrete 

    gᶻ_D = g(params.p.Z.D*(D-params.Jₜₕᵣ.Z.D), params.gₘₐₓ⁰.Z*params.b.Z^T, Fₗᵢₘ(params.p.Z, params.Jₜₕᵣ.Z, params.Fₜₕᵣ.Z, (; P, D, POC)), F(params.p.Z, params.Jₜₕᵣ.Z, (; P, D, POC)), params.K_G.Z, z_food_total)
    gᴹ_D = g(params.p.M.D*(D-params.Jₜₕᵣ.M.D), params.gₘₐₓ⁰.M*params.b.M^T, Fₗᵢₘ(params.p.M, params.Jₜₕᵣ.M, params.Fₜₕᵣ.M, (; P, D, POC, Z)), F(params.p.M, params.Jₜₕᵣ.M, (; P, D, POC, Z)), params.K_G.M, m_food_total)

    return θₒₚₜˢⁱᴰ*(1 - params.δ.D)*μᴰ*D - params.m.D*D*Siᴰ/(params.Kₘ+D) - sh*(params.wᴾ+ params.wₘₐₓᴰ*(1-Lₗᵢₘᴰ))*D*Siᴰ - (Siᴰ/D)*(gᶻ_D*Z + gᴹ_D*M)#eq 17
end