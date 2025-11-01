# Contributors

Thank you to everyone who has contributed to Z6!

## Core Team

- **[@copyleftdev](https://github.com/copyleftdev)** - Project Creator & Maintainer

## Philosophy

Z6 is built with **Tiger Style** discipline:
- Zero technical debt
- Test before implement
- Minimum 2 assertions per function
- All loops are bounded
- Explicit error handling only

## How to Contribute

See [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) for detailed contribution guidelines.

### Quick Start

1. **Fork the repository**
2. **Create a feature branch** following our naming convention:
   - `feat/TASK-XXX-description` for features
   - `fix/TASK-XXX-description` for bug fixes
   - `docs/TASK-XXX-description` for documentation

3. **Follow Tiger Style**:
   - Minimum 2 assertions per function
   - Bounded loops only (no unbounded `while(true)`)
   - Explicit error handling (no `catch {}`)
   - Run `zig fmt` before committing

4. **Write tests first** (TDD):
   - Add tests before implementation
   - Minimum 90% code coverage
   - Fuzz test all parsers (1M+ inputs)

5. **Pre-commit checks**:
   ```bash
   ./scripts/install-hooks.sh  # Install once
   git commit                   # Runs validation automatically
   ```

6. **Submit a Pull Request**:
   - Reference the issue number
   - Fill out the PR template completely
   - Ensure all CI checks pass
   - Request review from maintainers

## Code of Conduct

- **Be respectful** - We're all learning and building together
- **Be constructive** - Critique code, not people
- **Be explicit** - No assumptions, make everything clear
- **Be rigorous** - Tiger Style demands precision

## Recognition

Contributors will be:
- Listed in this file
- Credited in release notes
- Mentioned in project announcements

## License

By contributing to Z6, you agree that your contributions will be licensed under the MIT License.

---

**"Do it right the first time. Zero technical debt."** — Tiger Style
