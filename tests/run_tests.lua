local repo_root = "/home/runner/work/Entropy-Cardsleeve/Entropy-Cardsleeve"
local target_file = repo_root .. "/EntropyEvolution/EntropyEvolution.lua"

local results = { passed = 0, failed = 0 }

local function fail(message)
    error(message, 2)
end

local function assert_true(value, message)
    if not value then
        fail(message or "expected true")
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        fail((message or "values are not equal") .. string.format(" (expected=%s, actual=%s)", tostring(expected), tostring(actual)))
    end
end

local function run_test(name, fn)
    io.write("TEST ", name, " ... ")
    local ok, err = pcall(fn)
    if ok then
        results.passed = results.passed + 1
        io.write("PASS\n")
    else
        results.failed = results.failed + 1
        io.write("FAIL\n", err, "\n")
    end
end

local function build_card(set_name)
    return {
        ability = { set = set_name or "Default" },
        set_edition_calls = 0,
        set_seal_calls = 0,
        set_ability_calls = 0,
        set_edition = function(self, edition)
            self.edition = edition
            self.set_edition_calls = self.set_edition_calls + 1
        end,
        set_seal = function(self, seal)
            self.seal = seal
            self.set_seal_calls = self.set_seal_calls + 1
        end,
        set_ability = function(self, ability)
            self.assigned_ability = ability
            self.set_ability_calls = self.set_ability_calls + 1
        end
    }
end

local function build_joker(key)
    return {
        config = { center = { key = key } },
        set_edition_calls = 0,
        set_edition = function(self, edition)
            self.edition = edition
            self.set_edition_calls = self.set_edition_calls + 1
        end
    }
end

local function setup_environment()
    _G.print = function() end
    _G.number_format = function(num)
        return "n:" .. tostring(num)
    end

    _G.G = {
        P_SEALS = { Gold = true, Red = true, Blue = true },
        P_CENTERS = {
            m_bonus = { key = "m_bonus" },
            m_mult = { key = "m_mult" }
        },
        P_CENTER_POOLS = {
            Enhanced = {
                { key = "m_bonus" },
                { key = "m_stone" },
                { key = "m_mult" }
            },
            Edition = {
                { key = "e_foil", e_switch_point = 1 },
                { key = "e_negative", e_switch_point = 1 }
            }
        },
        GAME = {},
        FUNCS = {
            draw_from_discard_to_hand = function(e)
                return "orig:" .. tostring(e or "")
            end
        },
        discard = { cards = {} },
        hand = {
            cards = {},
            juice_up = function() end
        },
        jokers = { cards = {} },
        E_MANAGER = {
            add_event = function(_, event)
                if event and event.func then
                    event.func()
                end
            end
        }
    }

    _G.Event = function(def)
        return def
    end

    _G.SMODS = {
        current_mod = {},
        Atlas = function() end
    }

    _G.__SLEEVE_DEF = nil
    _G.CardSleeves = {
        Sleeve = function(def)
            _G.__SLEEVE_DEF = def
        end
    }

    _G.__ENTROPY_TESTING = true
    _G.__ENTROPY_TEST_EXPORTS = nil
    dofile(target_file)
    assert_true(_G.__ENTROPY_TEST_EXPORTS ~= nil, "test exports not initialized")
end

setup_environment()
local exports = _G.__ENTROPY_TEST_EXPORTS

run_test("startup sanitization removes invalid editions", function()
    G.P_CENTER_POOLS.Edition = {
        { key = "e_foil", e_switch_point = 1 },
        { key = "e_base", e_switch_point = 1 },
        { key = "e_holo" },
        { key = 123, e_switch_point = 1 },
        { key = "e_negative", e_switch_point = 2 }
    }

    exports.sanitize_editions_startup()

    assert_eq(#G.P_CENTER_POOLS.Edition, 2, "expected only valid editions")
    assert_eq(G.P_CENTER_POOLS.Edition[1].key, "e_foil")
    assert_eq(G.P_CENTER_POOLS.Edition[2].key, "e_negative")
end)

run_test("enhancement pool excludes stone enhancement", function()
    local enhancements = exports.build_enhancement_pool()
    assert_eq(#enhancements, 2)
    assert_eq(enhancements[1], "m_bonus")
    assert_eq(enhancements[2], "m_mult")
end)

run_test("edition pool includes validated and base editions", function()
    G.P_CENTER_POOLS.Edition = {
        { key = "e_holo", e_switch_point = 1 },
        { key = "e_negative", e_switch_point = 1 },
        { key = "e_base", e_switch_point = 1 },
        { key = "e_custom", e_switch_point = 1 }
    }

    local editions = exports.build_edition_pool()
    local seen = {}
    for _, edition in ipairs(editions) do
        seen[edition] = true
    end

    assert_true(seen.holo, "missing holo")
    assert_true(seen.negative, "missing negative")
    assert_true(seen.custom, "missing custom edition")
    assert_true(seen.foil, "missing ensured base foil")
    assert_true(seen.polychrome, "missing ensured base polychrome")
end)

run_test("propagation history is capped", function()
    exports.reset_state()
    for i = 1, 60 do
        exports.propagate_modifiers("ed" .. i, "seal" .. i, "enh" .. i)
    end

    assert_eq(exports.get_state().propagated_count, 50, "history limit should cap to 50")
end)

run_test("joker mutation chance scales and caps", function()
    exports.reset_state()
    assert_eq(exports.get_joker_mutation_chance(), 0.15)

    for i = 1, 25 do
        exports.propagate_modifiers("ed", "seal", "enh")
    end
    assert_eq(exports.get_joker_mutation_chance(), 0.25)

    for i = 1, 200 do
        exports.propagate_modifiers("ed", "seal", "enh")
    end
    assert_eq(exports.get_joker_mutation_chance(), 0.35)
end)

run_test("hand resonance mutates at most two default cards", function()
    exports.reset_state()
    G.hand.cards = {
        build_card("Default"),
        build_card("Default"),
        build_card("Default"),
        build_card("Joker")
    }

    local original_random = math.random
    math.random = function(a, b)
        if a and b then return a end
        if a then return 1 end
        return 0
    end

    exports.apply_hand_resonance()

    math.random = original_random

    local mutated_default = 0
    for i = 1, 3 do
        if G.hand.cards[i].set_edition_calls > 0 then
            mutated_default = mutated_default + 1
        end
    end
    assert_eq(mutated_default, 2, "should mutate only two default cards")
    assert_eq(G.hand.cards[4].set_edition_calls, 0, "non-default card must not mutate")
end)

run_test("joker modifiers skip dominated jokers", function()
    exports.reset_state()
    local joker = build_joker("j_perkeo")
    exports.apply_joker_modifiers(joker)
    assert_eq(joker.set_edition_calls, 0)
end)

run_test("sleeve apply wraps discard draw hook once", function()
    exports.reset_state()
    assert_true(__SLEEVE_DEF ~= nil, "sleeve definition missing")

    local card = build_card("Default")
    G.discard.cards = { card }
    G.GAME.entropy_hooks_applied = nil

    local original_random = math.random
    math.random = function(a, b)
        if a and b then return a end
        if a then return 1 end
        return 0
    end

    __SLEEVE_DEF.apply(__SLEEVE_DEF)
    local wrapped_once = G.FUNCS.draw_from_discard_to_hand
    local result = wrapped_once("x")
    __SLEEVE_DEF.apply(__SLEEVE_DEF)
    local wrapped_twice = G.FUNCS.draw_from_discard_to_hand

    math.random = original_random

    assert_eq(result, "orig:x")
    assert_eq(card.set_edition_calls, 1, "discard hook should mutate default discard cards")
    assert_true(wrapped_once == wrapped_twice, "hook should not be re-wrapped")
end)

io.write(string.format("\nPassed: %d  Failed: %d\n", results.passed, results.failed))
if results.failed > 0 then
    os.exit(1)
end
