-- ============================================================
--  ENTROPY EVOLUTION (FAST MODE + BURST ANIMATION + CRASH FIX)
-- ============================================================

--------------------------------------------------
--  GLOBAL FAILSAFE: PATCH number_format TO PREVENT CRASHES
--------------------------------------------------
local _orig_number_format = number_format

number_format = function(num, ...)
    -- If original isn't ready yet, just stringify
    if type(_orig_number_format) ~= "function" then
        return tostring(num)
    end

    -- If something upstream passes garbage, don't crash
    local ok, result = pcall(_orig_number_format, num, ...)
    if ok and result ~= nil then
        return result
    end

    -- Fallback: plain string
    return tostring(num)
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
            print("EntropyEvolution: Removed invalid edition at startup:", center and center.key)
        end
    end

    G.P_CENTER_POOLS.Edition = cleaned
end

sanitize_editions_startup()

--------------------------------------------------
--  ENTROPY EVOLUTION SYSTEM
--------------------------------------------------

local mod = SMODS.current_mod

local INCLUDE_BASE_GAME = true
local INCLUDE_MODDED = true

local PROPAGATED_MODIFIERS = {}
local CACHED_POOLS = nil

local EDITIONS_BASE = {"foil", "holo", "polychrome", "negative"}
local PROPAGATION_HISTORY_LIMIT = 50
local JOKER_MUTATION_BASE_CHANCE = 0.15
local JOKER_MUTATION_MEMORY_SCALING = 0.004
local JOKER_MUTATION_MEMORY_CAP = 0.2
local HAND_RESONANCE_CHANCE = 0.12
local HAND_RESONANCE_MAX_CARDS = 2
local CARD_SET_DEFAULT = "Default"

--------------------------------------------------
-- HELPERS
--------------------------------------------------
local function rand(tbl)
    if not tbl or #tbl == 0 then return nil end
    return tbl[math.random(1, #tbl)]
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
            if not dominated[center.key] then
                table.insert(enhancements, center.key)
            end
        end
    elseif INCLUDE_BASE_GAME then
        local base = {"m_bonus", "m_mult", "m_wild", "m_glass", "m_steel", "m_lucky"}
        for _, e in ipairs(base) do table.insert(enhancements, e) end
    end

    return enhancements
end

-- VALIDATED EDITION POOL
local function build_edition_pool()
    local editions = {}

    if G.P_CENTER_POOLS and G.P_CENTER_POOLS.Edition then
        for _, center in ipairs(G.P_CENTER_POOLS.Edition) do
            if center
            and center.key
            and type(center.key) == "string"
            and center.key ~= "e_base"
            and center.e_switch_point ~= nil
            then
                local ed = center.key:gsub("^e_", "")
                if ed ~= "" then table.insert(editions, ed) end
            end
        end
    end

    -- Ensure base editions exist
    local exists = {}
    for _, ed in ipairs(editions) do exists[ed] = true end
    for _, ed in ipairs(EDITIONS_BASE) do
        if not exists[ed] then table.insert(editions, ed) end
    end

    return editions
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
    if #PROPAGATED_MODIFIERS > PROPAGATION_HISTORY_LIMIT then table.remove(PROPAGATED_MODIFIERS, 1) end
end

--------------------------------------------------
-- CACHE POOLS
--------------------------------------------------
local function get_pools()
    if not CACHED_POOLS then
        CACHED_POOLS = {
            seals = build_seal_pool(),
            enhancements = build_enhancement_pool(),
            editions = build_edition_pool()
        }
    end
    return CACHED_POOLS
end

--------------------------------------------------
-- APPLY TO CARDS
--------------------------------------------------
local function apply_card_modifiers(card)
    if not card or not card.set_edition then return end

    local pools = get_pools()

    local edition = inherit_modifier("edition") or rand(pools.editions)
    if math.random() < 0.2 then edition = rand(pools.editions) end

    local seal = inherit_modifier("seal") or rand(pools.seals)
    if math.random() < 0.3 then seal = rand(pools.seals) end

    local enhancement = inherit_modifier("enhancement") or rand(pools.enhancements)
    if math.random() < 0.4 then enhancement = rand(pools.enhancements) end

    if edition then card:set_edition({[edition] = true}, true, true) end
    if seal then card:set_seal(seal, true) end
    if enhancement and G.P_CENTERS[enhancement] then
        card:set_ability(G.P_CENTERS[enhancement], true, true)
    end

    propagate_modifiers(edition, seal, enhancement)
end

--------------------------------------------------
-- APPLY TO JOKERS
--------------------------------------------------
local function apply_joker_modifiers(joker)
    if not joker or joker.edition then return end

    local dominated = {
        j_perkeo = true, j_cry_perkeo = true,
        j_caino = true, j_triboulet = true,
        j_yorick = true, j_chicot = true,
    }

    if joker.config and joker.config.center and dominated[joker.config.center.key] then
        return
    end

    local editions = get_pools().editions

    -- Break inheritance 50% of the time
    local edition = inherit_modifier("edition")
    if math.random() < 0.5 then edition = nil end

    edition = edition or rand(editions)
    if math.random() < 0.3 then edition = rand(editions) end

    local ok = pcall(function()
        joker:set_edition({[edition] = true}, true, true)
    end)

    if ok then propagate_modifiers(edition, nil, nil) end
end

local function get_joker_mutation_chance()
    local memory_bonus = math.min(#PROPAGATED_MODIFIERS * JOKER_MUTATION_MEMORY_SCALING, JOKER_MUTATION_MEMORY_CAP)
    return JOKER_MUTATION_BASE_CHANCE + memory_bonus
end

local function apply_hand_resonance()
    if not G.hand or not G.hand.cards then return end

    local mutated = 0
    for _, card in ipairs(G.hand.cards) do
        if mutated >= HAND_RESONANCE_MAX_CARDS then break end
        if card.ability and card.ability.set == CARD_SET_DEFAULT and math.random() < HAND_RESONANCE_CHANCE then
            apply_card_modifiers(card)
            mutated = mutated + 1
        end
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
            "{C:inactive}(Stone enhancement blacklisted){}"
        }
    },

    atlas = "sleeve_atlas",
    pos = {x = 0, y = 0},
    config = {},

    apply = function(self)
        PROPAGATED_MODIFIERS = {}
        CACHED_POOLS = nil

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

                for _, card in ipairs(G.discard.cards) do
                    if card.ability and card.ability.set == CARD_SET_DEFAULT then
                        apply_card_modifiers(card)
                    end
                end

                G.E_MANAGER:add_event(Event({
                    func = function()
                        G.hand:juice_up(0.4, 0.4)
                        return true
                    end
                }))
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
        return {vars = {}}
    end
}
