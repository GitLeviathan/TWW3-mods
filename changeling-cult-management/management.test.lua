local logic = dofile("management.lua")
local buildings = {
    income1 = {group="gold", share=.50, host_bonus=.10},
    income2 = {group="gold", share=.75, host_bonus=.25},
    income3 = {group="gold", share=1, host_bonus=.50},
    tribute = {group="gold", flat_gold=150, host_bonus=-.10},
    books1 = {group="books", books=8},
    books2 = {group="books", books=12},
    spread1 = {group="spread", spread=2},
    spread2 = {group="spread", spread=4},
}
local sites = {
    wei = {name="Вэй-Цзинь", gdp=8000, provinces=2, targets=3},
    hai = {name="Хайчай", gdp=2200, provinces=0, targets=0},
    red = {name="Красная крепость", gdp=2700, provinces=1, targets=2},
    fort = {name="Форт Оберштир", gdp=1600, provinces=4, targets=5},
}
local function job(region, slot, level, current, kind, gold, supplies)
    return {
        region=region, slot=slot, level=level, current=current, kind=kind,
        gold=gold or 1000, supplies=supplies or 10, turns=2, affordable=true,
    }
end
local jobs = {
    job("wei", 1, "income2", "income1", "upgrade", 2000, 20),
    job("wei", 2, "tribute", nil, "build"),
    job("hai", 3, "income3", "income2", "upgrade", 3000, 30),
    job("red", 4, "income1", "tribute", "upgrade", 1600, 10),
    job("fort", 5, "books2", "books1", "upgrade", 1700, 10),
    job("red", 6, "books1", nil, "build", 1000, 15),
    job("wei", 7, "books1", nil, "build", 1000, 10),
    job("wei", 7, "spread1", nil, "build"),
    job("wei", 9, "spread1", nil, "build"),
    job("red", 6, "spread1", nil, "build"),
    job("fort", 8, "spread2", "spread1", "upgrade"),
    job("fort", 10, "spread1", nil, "build"),
    job("hai", 11, "spread1", "spread1", "remove", 0, 0),
    job("fort", 8, "spread1", "spread1", "remove", 0, 0),
    job("hai", 12, "books1", "books1", "remove", 0, 0),
}
local rows = logic.rank(jobs, sites, buildings)
assert(#rows.gold==3 and rows.gold[1].region=="wei" and rows.gold[2].region=="red")
assert(rows.gold[1].gain==2818 and rows.gold[1].payback<1 and rows.gold[2].gain==1500)
assert(#rows.books==3 and rows.books[1].region=="wei" and rows.books[2].region=="red")
assert(#rows.spread==3 and rows.spread[1].region=="wei" and rows.spread[2].region=="red")
assert(rows.spread[3].region=="fort" and rows.spread[3].kind=="upgrade")
assert(#rows.remove==1 and rows.remove[1].region=="hai")
local preset = logic.preset(jobs, buildings, "wei", {"books1", "spread1"})
assert(#preset==2 and preset[1].slot~=preset[2].slot)
assert(not logic.preset(jobs, buildings, "wei", {"books1","books1"}))
assert(not logic.preset(jobs, buildings, "hai", {"books1"}))
local gold,supplies = logic.total(preset)
assert(gold==2000 and supplies==20)
assert(not logic.same(jobs[1], job("wei",1,"income2","income1","upgrade",1999,20)))
assert(logic.same(jobs[1], job("wei",1,"income2","income1","upgrade",2000,20)))
print("Cult management: return on investment, cost sorting, spread order, demolition, distinct preset slots and revalidation passed")
