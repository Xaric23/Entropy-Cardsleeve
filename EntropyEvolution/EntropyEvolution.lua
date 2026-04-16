-- ============================================================
--  ENTROPY EVOLUTION (ENHANCED VERSION)
--  Features: Config System, Weighted Rarities, Streak Bonuses,
--            Combo System, Debug Mode, Improved Balance
-- ============================================================

--------------------------------------------------
--  CONFIGURATION SYSTEM
--------------------------------------------------
local CONFIG = {
    -- Core chances
    edition_override_chance = 0.2,
    seal_override_chance = 0.3,
    enhancement_override_chance = 0.4,
    joker_inheritance_break_chance = 0.5,
    joker_edition_override_chance = 0.3,

    -- Mutation settings
    joker_mutation_base_chance = 0.15,
    joker_mutation_memory_scaling = 0.004,
    joker_mutation_max_bonus = 0.2,

    -- Hand resonance
    hand_resonance_chance = 0.12,
    hand_resonance_max_cards = 2,

    -- Streak system
    streak_bonus_per_level = 0.02,
    streak_max_bonus = 0.15,
    streak_decay_chance = 0.3,

    -- Evolution tracking
    propagation_history_limit = 50,

    -- Debug mode
    debug_mode = false,

    -- Weighted edition pools (higher weight = more common)
    edition_weights = {
        foil = 40,
        holo = 30,
        polychrome = 20,
        negative = 10
    },

    -- Combo bonuses (synergistic modifier pairs)
    combo_bonuses = {
        { edition = "polychrome", seal = "Gold", bonus_mult = 1.5 },
        { edition = "negative", enhancement = "m_glass", bonus_mult = 1.3 },
        { edition = "holo", seal = "Red", bonus_mult = 1.2 },
        { seal = "Purple", enhancement = "m_lucky", bonus_mult = 1.4 }
    }
}

--------------------------------------------------
--  GLOBAL FAILSAFE: PATCH number_format TO PREVENT CRASHES
--------------------------------------------------
local _orig_number_format = number_format

number_format = function(num, ...)
    if type(_orig_number_format) ~= "function" then
        return tostring(num)
    end

    local ok, result = pcall(_orig_number_format, num, ...)
    if ok and result ~= nil then
        return result
    end

    return tostring(num)
end

--------------------------------------------------
--  DEBUG LOGGING
--------------------------------------------------
local function debug_log(...)
    if CONFIG.debug_mode then
        print("[EntropyEvolution]", ...)
    end
end

--------------------------------------------------
--  HARD PATCH: FIX BROKEN EDITIONS AT STARTUP
--------------------------------------------------
local function sanitize_editions_startup()
    if not G or not G.P_CENTER_POOLS or not G.P_CENTER_POOLS.Edition then return end

    local cleaned = {}
    for _, center in ipairs(G.P_CENTER_POOLS.Edition) do
        if center
        and center.key
        and type(center.key) == "string"
        and center.key ~= "e_base"
        and center.e_switch_point ~= nil
        then
            table.insert(cleaned, center)
        else
            debug_log("Removed invalid edition at startup:", center and center.key)
        end
    end

    G.P_CENTER_POOLS.Edition = cleaned
end

sanitize_editions_startup()

--------------------------------------------------
--  ENTROPY EVOLUTION STATE
--------------------------------------------------
local mod = SMODS.current_mod

local INCLUDE_BASE_GAME = true
local INCLUDE_MODDED = true

local PROPAGATED_MODIFIERS = {}
local CACHED_POOLS = nil
local EVOLUTION_STATS = {
    total_mutations = 0,
    current_streak = 0,
    best_streak = 0,
    combos_triggered = 0,
    editions_applied = {},
    seals_applied = {},
    enhancements_applied = {}
}

local EDITIONS_BASE = {"foil", "holo", "polychrome", "negative"}
local CARD_SET_DEFAULT = "Default"

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function rand(tbl)
    if not tbl or #tbl == 0 then return nil end
    return tbl[math.random(1, #tbl)]
end

local function weighted_random(weights)
    local total = 0
    for _, weight in pairs(weights) do
        total = total + weight
    end

    local roll = math.random() * total
    local cumulative = 0

    for key, weight in pairs(weights) do
        cumulative = cumulative + weight
        if roll <= cumulative then
            return key
        end
    end

    -- Fallback
    for key, _ in pairs(weights) do
        return key
    end
end

local function clamp(value, min_val, max_val)
    return math.max(min_val, math.min(max_val, value))
end

--------------------------------------------------
-- STREAK SYSTEM
--------------------------------------------------
local function update_streak(success)
    if success then
        EVOLUTION_STATS.current_streak = EVOLUTION_STATS.current_streak + 1
        if EVOLUTION_STATS.current_streak > EVOLUTION_STATS.best_streak then
            EVOLUTION_STATS.best_streak = EVOLUTION_STATS.current_streak
        end
        debug_log("Streak increased to", EVOLUTION_STATS.current_streak)
    else
        if math.random() < CONFIG.streak_decay_chance then
            EVOLUTION_STATS.current_streak = math.max(0, EVOLUTION_STATS.current_streak - 1)
            debug_log("Streak decayed to", EVOLUTION_STATS.current_streak)
        end
    end
end

local function get_streak_bonus()
    local bonus = EVOLUTION_STATS.current_streak * CONFIG.streak_bonus_per_level
    return clamp(bonus, 0, CONFIG.streak_max_bonus)
end

--------------------------------------------------
-- COMBO SYSTEM
--------------------------------------------------
local function check_combo(edition, seal, enhancement)
    for _, combo in ipairs(CONFIG.combo_bonuses) do
        local matches = true

        if combo.edition and combo.edition ~= edition then matches = false end
        if combo.seal and combo.seal ~= seal then matches = false end
        if combo.enhancement and combo.enhancement ~= enhancement then matches = false end

        -- Need at least 2 matching components
        local component_count = 0
        if combo.edition then component_count = component_count + 1 end
        if combo.seal then component_count = component_count + 1 end
        if combo.enhancement then component_count = component_count + 1 end

        if matches and component_count >= 2 then
            EVOLUTION_STATS.combos_triggered = EVOLUTION_STATS.combos_triggered + 1
            debug_log("Combo triggered!", edition, seal, enhancement, "Bonus:", combo.bonus_mult)
            return combo.bonus_mult
        end
    end
    return 1.0
end

--------------------------------------------------
-- STATS TRACKING
--------------------------------------------------
local function track_mutation(edition, seal, enhancement)
    EVOLUTION_STATS.total_mutations = EVOLUTION_STATS.total_mutations + 1

    if edition then
        EVOLUTION_STATS.editions_applied[edition] = (EVOLUTION_STATS.editions_applied[edition] or 0) + 1
    end
    if seal then
        EVOLUTION_STATS.seals_applied[seal] = (EVOLUTION_STATS.seals_applied[seal] or 0) + 1
    end
    if enhancement then
        EVOLUTION_STATS.enhancements_applied[enhancement] = (EVOLUTION_STATS.enhancements_applied[enhancement] or 0) + 1
    end
end

local function get_evolution_stats()
    return {
        total_mutations = EVOLUTION_STATS.total_mutations,
        current_streak = EVOLUTION_STATS.current_streak,
        best_streak = EVOLUTION_STATS.best_streak,
        combos_triggered = EVOLUTION_STATS.combos_triggered,
        streak_bonus = get_streak_bonus()
    }
end

--------------------------------------------------
-- BUILD POOLS (with validation)
--------------------------------------------------
local function build_seal_pool()
    local seals = {}
    if G.P_SEALS then
        for key, _ in pairs(G.P_SEALS) do
            table.insert(seals, key)
        end
    elseif INCLUDE_BASE_GAME then
        seals = {"Gold", "Red", "Blue", "Purple"}
    end
    return seals
end

local function build_enhancement_pool()
    local enhancements = {}
    local dominated = {m_stone = true}

    if G.P_CENTER_POOLS and G.P_CENTER_POOLS.Enhanced then
        for _, center in ipairs(G.P_CENTER_POOLS.Enhanced) do
            if type(center) == "table"
            and type(center.key) == "string"
            and not dominated[center.key]
            then
                table.insert(enhancements, center.key)
            end
        end
    elseif INCLUDE_BASE_GAME then
        local base = {"m_bonus", "m_mult", "m_wild", "m_glass", "m_steel", "m_lucky"}
        for _, e in ipairs(base) do table.insert(enhancements, e) end
    end

    return enhancements
end

local function build_edition_pool()
    local editions = {}
    local edition_weights = {}

    if G.P_CENTER_POOLS and G.P_CENTER_POOLS.Edition then
        for _, center in ipairs(G.P_CENTER_POOLS.Edition) do
            if center
            and center.key
            and type(center.key) == "string"
            and center.key ~= "e_base"
            and center.e_switch_point ~= nil
            then
                local ed = center.key:gsub("^e_", "")
                if ed ~= "" then
                    table.insert(editions, ed)
                    edition_weights[ed] = CONFIG.edition_weights[ed] or 25
                end
            end
        end
    end

    local exists = {}
    for _, ed in ipairs(editions) do exists[ed] = true end
    for _, ed in ipairs(EDITIONS_BASE) do
        if not exists[ed] then
            table.insert(editions, ed)
            edition_weights[ed] = CONFIG.edition_weights[ed] or 25
        end
    end

    return editions, edition_weights
end

--------------------------------------------------
-- INHERITANCE
--------------------------------------------------
local function inherit_modifier(mod_type)
    if #PROPAGATED_MODIFIERS == 0 then return nil end
    local sample = rand(PROPAGATED_MODIFIERS)
    return sample and sample[mod_type]
end

local function propagate_modifiers(edition, seal, enhancement)
    table.insert(PROPAGATED_MODIFIERS, {
        edition = edition,
        seal = seal,
        enhancement = enhancement
    })
    if #PROPAGATED_MODIFIERS > CONFIG.propagation_history_limit then
        table.remove(PROPAGATED_MODIFIERS, 1)
    end
end

--------------------------------------------------
-- CACHE POOLS
--------------------------------------------------
local function get_pools()
    if not CACHED_POOLS then
        local editions, edition_weights = build_edition_pool()
        CACHED_POOLS = {
            seals = build_seal_pool(),
            enhancements = build_enhancement_pool(),
            editions = editions,
            edition_weights = edition_weights
        }
    end
    return CACHED_POOLS
end

--------------------------------------------------
-- WEIGHTED EDITION SELECTION
--------------------------------------------------
local function select_weighted_edition()
    local pools = get_pools()
    if pools.edition_weights and next(pools.edition_weights) then
        return weighted_random(pools.edition_weights)
    end
    return rand(pools.editions)
end

--------------------------------------------------
-- APPLY TO CARDS (Enhanced)
--------------------------------------------------
local function apply_card_modifiers(card)
    if not card or not card.set_edition then return false end

    local pools = get_pools()
    local streak_bonus = get_streak_bonus()

    -- Edition selection with weighted pools
    local edition = inherit_modifier("edition")
    if math.random() < (CONFIG.edition_override_chance + streak_bonus) then
        edition = select_weighted_edition()
    end
    edition = edition or select_weighted_edition()

    -- Seal selection
    local seal = inherit_modifier("seal")
    if math.random() < (CONFIG.seal_override_chance + streak_bonus) then
        seal = rand(pools.seals)
    end
    seal = seal or rand(pools.seals)

    -- Enhancement selection
    local enhancement = inherit_modifier("enhancement")
    if math.random() < (CONFIG.enhancement_override_chance + streak_bonus) then
        enhancement = rand(pools.enhancements)
    end
    enhancement = enhancement or rand(pools.enhancements)

    -- Apply modifiers
    local success = false
    if edition then
        local ok = pcall(function()
            card:set_edition({[edition] = true}, true, true)
        end)
        success = success or ok
    end

    if seal then
        local ok = pcall(function()
            card:set_seal(seal, true)
        end)
        success = success or ok
    end

    if enhancement and G.P_CENTERS[enhancement] then
        local ok = pcall(function()
            card:set_ability(G.P_CENTERS[enhancement], true, true)
        end)
        success = success or ok
    end

    if success then
        propagate_modifiers(edition, seal, enhancement)
        track_mutation(edition, seal, enhancement)
        update_streak(true)
        check_combo(edition, seal, enhancement)
        debug_log("Card mutated:", edition, seal, enhancement)
    end

    return success
end

--------------------------------------------------
-- APPLY TO JOKERS (Enhanced)
--------------------------------------------------
local function apply_joker_modifiers(joker)
    if not joker or joker.edition then return false end

    local dominated = {
        j_perkeo = true, j_cry_perkeo = true,
        j_caino = true, j_triboulet = true,
        j_yorick = true, j_chicot = true,
    }

    if joker.config and joker.config.center and dominated[joker.config.center.key] then
        return false
    end

    local streak_bonus = get_streak_bonus()

    -- Break inheritance with adjusted chance
    local edition = inherit_modifier("edition")
    if math.random() < (CONFIG.joker_inheritance_break_chance - streak_bonus) then
        edition = nil
    end

    edition = edition or select_weighted_edition()
    if math.random() < CONFIG.joker_edition_override_chance then
        edition = select_weighted_edition()
    end

    local ok = pcall(function()
        joker:set_edition({[edition] = true}, true, true)
    end)

    if ok then
        propagate_modifiers(edition, nil, nil)
        track_mutation(edition, nil, nil)
        update_streak(true)
        debug_log("Joker mutated:", edition)
    end

    return ok
end

local function get_joker_mutation_chance()
    local memory_bonus = math.min(
        #PROPAGATED_MODIFIERS * CONFIG.joker_mutation_memory_scaling,
        CONFIG.joker_mutation_max_bonus
    )
    return CONFIG.joker_mutation_base_chance + memory_bonus + get_streak_bonus()
end

local function apply_hand_resonance()
    if not G.hand or not G.hand.cards then return end

    local mutated = 0
    for _, card in ipairs(G.hand.cards) do
        if mutated >= CONFIG.hand_resonance_max_cards then break end
        local adjusted_chance = CONFIG.hand_resonance_chance + get_streak_bonus()
        if card.ability and card.ability.set == CARD_SET_DEFAULT and math.random() < adjusted_chance then
            if apply_card_modifiers(card) then
                mutated = mutated + 1
            end
        end
    end

    if mutated == 0 then
        update_streak(false)
    end
end

--------------------------------------------------
-- ATLAS
--------------------------------------------------
SMODS.Atlas {
    key = "sleeve_atlas",
    path = "entropy_sleeve.png",
    px = 73,
    py = 95
}

--------------------------------------------------
-- SLEEVE REGISTRATION
--------------------------------------------------
CardSleeves.Sleeve {
    key = "entropy_evolution",
    name = "Entropy Sleeve",

    loc_txt = {
        name = "Entropy Sleeve",
        text = {
            "Discarded cards transform with",
            "{C:attention}evolving modifiers{}",
            "Shop Jokers gain random {C:edition}Editions{}",
            "{C:attention}Edition{}, {C:attention}Seal{}, {C:attention}Enhancement{} guaranteed",
            "{C:green}Streak system{} boosts mutation rates",
            "{C:inactive}(Stone enhancement blacklisted){}"
        }
    },

    atlas = "sleeve_atlas",
    pos = {x = 0, y = 0},
    config = {},

    apply = function(self)
        PROPAGATED_MODIFIERS = {}
        CACHED_POOLS = nil
        EVOLUTION_STATS = {
            total_mutations = 0,
            current_streak = 0,
            best_streak = 0,
            combos_triggered = 0,
            editions_applied = {},
            seals_applied = {},
            enhancements_applied = {}
        }

        if not G.GAME.entropy_hooks_applied then
            G.GAME.entropy_hooks_applied = true

            local orig = G.FUNCS.draw_from_discard_to_hand
            if orig then
                G.FUNCS.draw_from_discard_to_hand = function(e)
                    if G.discard and G.discard.cards then
                        for _, card in ipairs(G.discard.cards) do
                            if card.ability and card.ability.set == CARD_SET_DEFAULT then
                                apply_card_modifiers(card)
                            end
                        end
                    end
                    return orig(e)
                end
            end
        end
    end,

    calculate = function(self, sleeve, context)
        -- FAST END-OF-ROUND MUTATION + BURST ANIMATION
        if context.end_of_round and not context.game_over then
            CACHED_POOLS = nil
            if G.discard and G.discard.cards then
                local mutated_any = false

                for _, card in ipairs(G.discard.cards) do
                    if card.ability and card.ability.set == CARD_SET_DEFAULT then
                        if apply_card_modifiers(card) then
                            mutated_any = true
                        end
                    end
                end

                if mutated_any then
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            G.hand:juice_up(0.4, 0.4)
                            return true
                        end
                    }))
                end
            end
        end

        -- FAST JOKER EVOLUTION
        if context.setting_blind and not context.blueprint then
            CACHED_POOLS = nil
            local joker_mutation_chance = get_joker_mutation_chance()
            if G.jokers and G.jokers.cards then
                for _, joker in ipairs(G.jokers.cards) do
                    if not joker.edition and math.random() < joker_mutation_chance then
                        apply_joker_modifiers(joker)
                    end
                end
            end
            apply_hand_resonance()
        end
    end,

    loc_vars = function(self)
        local stats = get_evolution_stats()
        return {vars = {
            stats.total_mutations,
            stats.current_streak,
            stats.combos_triggered
        }}
    end
}

--------------------------------------------------
-- TEST EXPORTS
--------------------------------------------------
if rawget(_G, "__ENTROPY_TESTING") then
    _G.__ENTROPY_TEST_EXPORTS = {
        sanitize_editions_startup = sanitize_editions_startup,
        build_seal_pool = build_seal_pool,
        build_enhancement_pool = build_enhancement_pool,
        build_edition_pool = build_edition_pool,
        propagate_modifiers = propagate_modifiers,
        inherit_modifier = inherit_modifier,
        apply_card_modifiers = apply_card_modifiers,
        apply_joker_modifiers = apply_joker_modifiers,
        apply_hand_resonance = apply_hand_resonance,
        get_joker_mutation_chance = get_joker_mutation_chance,
        get_pools = get_pools,
        get_evolution_stats = get_evolution_stats,
        get_streak_bonus = get_streak_bonus,
        update_streak = update_streak,
        check_combo = check_combo,
        weighted_random = weighted_random,
        select_weighted_edition = select_weighted_edition,
        constants = {
            propagation_history_limit = CONFIG.propagation_history_limit
        },
        config = CONFIG,
        reset_state = function()
            PROPAGATED_MODIFIERS = {}
            CACHED_POOLS = nil
            EVOLUTION_STATS = {
                total_mutations = 0,
                current_streak = 0,
                best_streak = 0,
                combos_triggered = 0,
                editions_applied = {},
                seals_applied = {},
                enhancements_applied = {}
            }
        end,
        get_state = function()
            return {
                propagated_count = #PROPAGATED_MODIFIERS,
                cached_pools = CACHED_POOLS,
                evolution_stats = EVOLUTION_STATS
            }
        end
    }
end
