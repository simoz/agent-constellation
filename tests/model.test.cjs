const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Model.js'), 'utf8'), model);

test('roles stay stable and distinct while agents are visible', () => {
    const agents = ['a', 'b', 'c', 'd', 'e', 'f'].map(id => ({id, status: 'working'}));
    const roles = model.assignRoles(agents, {});
    assert.equal(new Set(Object.values(roles)).size, 6);
    const later = model.assignRoles([agents[2], {id: 'g', status: 'idle'}], roles);
    assert.equal(later.c, roles.c);
    assert.notEqual(later.g, later.c);
    assert.equal(model.agentRole({id: 'c', status: 'waiting'}, later), 'red');
});
test('file nodes keep a minimum angular gap and stable positions', () => {
    const files = Array.from({length: 12}, (_, i) => ({path: `app/file${i}.rb`, heat: i / 12}));
    const nodes = model.fileNodes({id: 'a', files}, 0, 0, 100);
    const angles = nodes.map(n => Math.atan2(n.y / 0.82, n.x)).sort((a, b) => a - b);
    const gaps = angles.map((a, i) => (i ? a - angles[i - 1] : a + Math.PI * 2 - angles[angles.length - 1]));
    assert.ok(Math.min(...gaps) > Math.PI * 2 / 12 * 0.6, `gaps ${gaps}`);
    assert.deepEqual(model.fileNodes({id: 'a', files}, 0, 0, 100).map(n => n.x), nodes.map(n => n.x));
});
test('centres stay inside the unit square', () => {
    for (let count = 1; count <= 24; count++)
        for (const aspect of [0.5, 1, 2.2])
            for (const c of model.centres(count, aspect)) assert.ok(c.x > 0 && c.x < 1 && c.y > 0 && c.y < 1);
});
test('labels', () => {
    assert.equal(model.tokens(950), '950');
    assert.equal(model.tokens(18400), '18k');
    assert.equal(model.tokens(1500), '1.5k');
    assert.equal(model.activityText({tool: 'Read', target: 'a.rb', subagent: 'Explore'}), 'Explore ▸ Read a.rb');
    assert.equal(model.summary([{status: 'waiting', subagents: [1], tokensPerMinute: 5, toolCalls: 2}]).waiting, 1);
});
