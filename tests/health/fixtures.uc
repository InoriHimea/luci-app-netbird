// SPDX-License-Identifier: Apache-2.0
import { readfile } from 'fs';
import { aggregate } from '../../luci-app-netbird/root/usr/share/netbird/health/model.uc';

let total = 0;
for (let path in ARGV) {
    let fixture = json(readfile(path));
    let result = aggregate(fixture.checks, fixture.options);
    for (let key, expected in fixture.expected) {
        if (key == 'coverage') {
            for (let vantage, state in expected)
                if (result.coverage[vantage] != state)
                    die(fixture.fixture + ': wrong ' + vantage + ' coverage\n');
        }
        else if (result[key] != expected)
            die(fixture.fixture + ': wrong ' + key + '\n');
    }
    if (result.expected_count != result.pass_count + result.fail_count + result.unknown_count +
        result.not_applicable_count + result.disabled_count)
        die(fixture.fixture + ': denominator mismatch\n');
    printf('PASS %s model replay: %s (%d expected, %d executed)\n',
        fixture.fixture, result.overall, result.expected_count, result.executed_count);
    total++;
}
if (!total) die('No fixtures supplied\n');
