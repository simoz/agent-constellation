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
test('only agents that start waiting raise an alert', () => {
    const agents = [{id: 'a', status: 'waiting'}, {id: 'b', status: 'waiting'}, {id: 'c', status: 'working'}];
    assert.equal(model.newlyWaiting(null, agents).length, 0);
    assert.deepEqual(Array.from(model.newlyWaiting(['a'], agents), a => a.id), ['b']);
    assert.deepEqual(Array.from(model.waitingIds(agents)), ['a', 'b']);
});
test('short paths keep their end', () => {
    assert.equal(model.shortPath('app/models/order.rb', 40), 'app/models/order.rb');
    assert.equal(model.shortPath('app/models/concerns/order.rb', 12), '…ns/order.rb');
    assert.equal(Array.from(model.shortPath('a/'.repeat(40) + 'end.rb', 20)).length, 20);
    assert.ok(model.shortPath('a/'.repeat(40) + 'end.rb', 20).endsWith('/end.rb'));
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
test('the scene key ignores sub-pixel motion and small heat changes', () => {
    const agent = {id: 'a', status: 'working', kind: 'Claude Code', project: 'shop', model: 'opus', subagents: [],
                   activity: {tool: 'Read', target: 'a.rb'}};
    const entry = (x, heat, added) => ({agent, x, y: 50, radius: 100, color: '#7aa2f7',
        files: [{path: 'a.rb', x: x + 40, y: 60, heat, file: {added, removed: 0}}]});
    const key = model.sceneKey([entry(10, 0.5, 1)]);
    assert.equal(model.sceneKey([entry(10.2, 0.51, 1)]), key);
    assert.notEqual(model.sceneKey([entry(11, 0.5, 1)]), key);
    assert.notEqual(model.sceneKey([entry(10, 0.6, 1)]), key);
    assert.notEqual(model.sceneKey([entry(10, 0.5, 2)]), key);
});
test('backdrop workspaces', () => {
    assert.deepEqual(Array.from(model.parseWorkspaces('')), []);
    assert.deepEqual(Array.from(model.parseWorkspaces(' 3 ')), [3]);
    assert.deepEqual(Array.from(model.parseWorkspaces('1-5')), [1, 2, 3, 4, 5]);
    assert.deepEqual(Array.from(model.parseWorkspaces('5, 1,3, 3')), [1, 3, 5]);
    for (const bad of ['0', '5-1', 'a', '1,,2', '100', '-1', '1-'])
        assert.equal(model.parseWorkspaces(bad), null, bad);
    assert.equal(model.formatWorkspaces([1, 2, 3, 4, 5]), '1-5');
    assert.equal(model.formatWorkspaces([1, 2, 5, 7, 8, 9]), '1, 2, 5, 7-9');
    assert.ok(model.validWorkspaces([1, 3]));
    assert.ok(!model.validWorkspaces([3, 1]) && !model.validWorkspaces([0]) && !model.validWorkspaces('1'));
    assert.ok(model.showsOnWorkspace([], 7) && model.showsOnWorkspace([2, 7], 7) && !model.showsOnWorkspace([2], 7));
});
test('wallpaper luminance picks the ink that stands out', () => {
    const grid = {columns: 4, rows: 2, values: [0, 0, 1, 1, 0, 0, 1, 1]};
    assert.equal(model.luminanceAt(grid, 0.1, 0.5, 0.05, 0.5), 0);
    assert.equal(model.luminanceAt(grid, 0.9, 0.5, 0.05, 0.5), 1);
    assert.equal(model.luminanceAt(grid, 0.5, 0.5, 0.5, 0.5), 0.5);
    assert.equal(model.luminanceAt({columns: 4, rows: 2, values: []}, 0.5, 0.5, 0.1, 0.1), -1);
    assert.equal(model.lightSurface(0.95, 0.1, 0.7), true);
    assert.equal(model.lightSurface(0.05, 0.1, 0.7), false);
    // Mid-grey favors the dark ink when the light ink is close to it.
    assert.equal(model.lightSurface(0.5, 0.1, 0.7), true);
});
