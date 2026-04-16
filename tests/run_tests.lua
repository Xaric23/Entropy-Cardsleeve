local script_path = debug.getinfo(1, "S").source:sub(2)
script_path = script_path:gsub("\\", "/")
if script_path:sub(1, 1) ~= "/" and not script_path:match("^%a:[/\\]") then
    local cwd = (os.getenv("PWD") or "."):gsub("\\", "/")
    script_path = cwd .. "/" .. script_path
end
local repo_root = script_path:match("^(.*)/tests/run_tests%.lua$")
if not repo_root then
    error("Unable to determine repository root from script path: " .. script_path)
end
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

local function assert_approx_eq(actual, expected, epsilon, message)
    if math.abs(actual - expected) > epsilon then
        error((message or "values are not approximately equal")
            .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
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

local function with_deterministic_random(fn)
    local original_random = math.random
    math.random = function(a, b)
        if a and b then return a end
        if a then return 1 end
        return 0
    end

    local ok, err = pcall(fn)
    math.random = original_random
    if not ok then
        error(err, 0)
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
        { key = false, e_switch_point = 1 },
        { key = {}, e_switch_point = 1 },
        { key = "e_negative", e_switch_point = 2 }
    }

    exports.sanitize_editions_startup()

    assert_eq(#G.P_CENTER_POOLS.Edition, 2, "expected only valid editions")
    assert_eq(G.P_CENTER_POOLS.Edition[1].key, "e_foil")
    assert_eq(G.P_CENTER_POOLS.Edition[2].key, "e_negative")
    for _, edition in ipairs(G.P_CENTER_POOLS.Edition) do
        assert_true(edition.key ~= "e_holo", "entries without e_switch_point must be removed")
    end
end)

run_test("enhancement pool excludes stone enhancement", function()
    local enhancements = exports.build_enhancement_pool()
    assert_eq(#enhancements, 2)
    assert_eq(enhancements[1], "m_bonus")
    assert_eq(enhancements[2], "m_mult")
end)

run_test("enhancement pool ignores invalid entries", function()
    local previous_enhanced = G.P_CENTER_POOLS.Enhanced
    local ok, err = pcall(function()
        G.P_CENTER_POOLS.Enhanced = {
            { key = "m_bonus" },
            false,
            "invalid",
            { key = false },
            {},
            { key = "m_stone" },
            { key = "m_mult" }
        }

        local enhancements = exports.build_enhancement_pool()
        assert_eq(#enhancements, 2)
        assert_eq(enhancements[1], "m_bonus")
        assert_eq(enhancements[2], "m_mult")
    end)
    G.P_CENTER_POOLS.Enhanced = previous_enhanced
    if not ok then
        error(err, 0)
    end
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
    local history_limit = exports.constants.propagation_history_limit
    local inserts = history_limit + 10
    for i = 1, inserts do
        exports.propagate_modifiers("ed" .. i, "seal" .. i, "enh" .. i)
    end

    assert_eq(exports.get_state().propagated_count, history_limit, "history limit should be enforced")
end)

run_test("joker mutation chance scales and caps", function()
    exports.reset_state()

    -- Base chance is 0.15
    assert_approx_eq(exports.get_joker_mutation_chance(), 0.15, 1e-9, "initial mutation chance should match")

    for i = 1, 25 do
        exports.propagate_modifiers("ed", "seal", "enh")
    end
    -- 0.15 + min(25 * 0.004, 0.2) = 0.15 + 0.1 = 0.25
    assert_approx_eq(exports.get_joker_mutation_chance(), 0.25, 1e-9, "mutation chance should scale after propagation")

    for i = 1, 200 do
        exports.propagate_modifiers("ed", "seal", "enh")
    end
    -- Capped at propagation_history_limit (50), so 0.15 + 0.2 = 0.35
    assert_approx_eq(exports.get_joker_mutation_chance(), 0.35, 1e-9, "mutation chance should cap at the maximum")
end)

run_test("hand resonance mutates at most two default cards", function()
    exports.reset_state()
    G.hand.cards = {
        build_card("Default"),
        build_card("Default"),
        build_card("Default"),
        build_card("Joker")
    }

    with_deterministic_random(function()
        exports.apply_hand_resonance()
    end)

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

run_test("joker modifiers can apply to non-dominated jokers", function()
    exports.reset_state()
    local joker = build_joker("j_not_dominated")
    with_deterministic_random(function()
        exports.apply_joker_modifiers(joker)
    end)
    assert_eq(joker.set_edition_calls, 1)
end)

run_test("sleeve apply wraps discard draw hook once", function()
    exports.reset_state()
    assert_true(__SLEEVE_DEF ~= nil, "sleeve definition missing")

    local card = build_card("Default")
    G.discard.cards = { card }
    G.GAME.entropy_hooks_applied = nil

    local wrapped_once
    local wrapped_twice
    local result
    with_deterministic_random(function()
        __SLEEVE_DEF.apply(__SLEEVE_DEF)
        wrapped_once = G.FUNCS.draw_from_discard_to_hand
        result = wrapped_once("x")
        __SLEEVE_DEF.apply(__SLEEVE_DEF)
        wrapped_twice = G.FUNCS.draw_from_discard_to_hand
    end)

    assert_eq(result, "orig:x")
    assert_eq(card.set_edition_calls, 1, "discard hook should mutate default discard cards")
    assert_true(wrapped_once == wrapped_twice, "hook should not be re-wrapped")
end)

-- NEW TESTS FOR v1.1.0 FEATURES

run_test("streak system increases on success", function()
    exports.reset_state()
    local initial_stats = exports.get_evolution_stats()
    assert_eq(initial_stats.current_streak, 0, "initial streak should be 0")

    exports.update_streak(true)
    local stats = exports.get_evolution_stats()
    assert_eq(stats.current_streak, 1, "streak should increase to 1")

    exports.update_streak(true)
    stats = exports.get_evolution_stats()
    assert_eq(stats.current_streak, 2, "streak should increase to 2")
end)

run_test("streak bonus is capped", function()
    exports.reset_state()

    -- Build up streak to max
    for i = 1, 20 do
        exports.update_streak(true)
    end

    local bonus = exports.get_streak_bonus()
    -- Config max is 0.15, streak_bonus_per_level is 0.02
    assert_true(bonus <= 0.15, "streak bonus should be capped at max")
end)

run_test("weighted random returns valid keys", function()
    local weights = { a = 50, b = 30, c = 20 }
    local result = exports.weighted_random(weights)
    assert_true(result == "a" or result == "b" or result == "c", "weighted_random should return valid key")
end)

run_test("combo system detects matching combos", function()
    exports.reset_state()
    local initial_stats = exports.get_evolution_stats()
    assert_eq(initial_stats.combos_triggered, 0, "initial combos should be 0")

    -- Trigger polychrome + Gold combo
    local bonus = exports.check_combo("polychrome", "Gold", nil)
    assert_eq(bonus, 1.5, "polychrome + Gold should give 1.5x bonus")

    local stats = exports.get_evolution_stats()
    assert_eq(stats.combos_triggered, 1, "combos_triggered should increment")
end)

run_test("combo system returns 1.0 for non-matching", function()
    exports.reset_state()
    local bonus = exports.check_combo("foil", "Blue", "m_bonus")
    assert_eq(bonus, 1.0, "non-matching combo should return 1.0")
end)

run_test("evolution stats track mutations", function()
    exports.reset_state()
    local card = build_card("Default")

    with_deterministic_random(function()
        exports.apply_card_modifiers(card)
    end)

    local stats = exports.get_evolution_stats()
    assert_true(stats.total_mutations >= 1, "total_mutations should be tracked")
end)

run_test("config values are accessible", function()
    assert_true(exports.config ~= nil, "config should be exposed")
    assert_eq(exports.config.joker_mutation_base_chance, 0.15, "default base chance should be 0.15")
    assert_eq(exports.config.streak_max_bonus, 0.15, "default streak max should be 0.15")
end)

io.write(string.format("\nPassed: %d  Failed: %d\n", results.passed, results.failed))
if results.failed > 0 then
    os.exit(1)
end
