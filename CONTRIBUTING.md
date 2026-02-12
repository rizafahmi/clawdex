# Contributing to Clawdex

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

1. **Prerequisites**: Elixir 1.18+ and Erlang/OTP 27+

2. **Clone and install dependencies:**

   ```sh
   git clone https://github.com/rizafahmi/clawdex.git
   cd clawdex
   mix deps.get
   ```

3. **Copy the example config:**

   ```sh
   mkdir -p ~/.clawdex
   cp config/config.example.json ~/.clawdex/config.json
   ```

4. **Run the tests:**

   ```sh
   mix test
   ```

## Code Quality

Before submitting a PR, please run the full quality check:

```sh
mix check
```

This runs:

- `mix format` — code formatting
- `mix credo --strict` — linting
- `mix dialyzer` — static analysis

## Pull Request Guidelines

1. **Fork** the repo and create your branch from `main`
2. **Write tests** for any new functionality
3. **Run `mix check`** and make sure everything passes
4. **Keep PRs focused** — one feature or fix per PR
5. **Write clear commit messages** following [Conventional Commits](https://www.conventionalcommits.org/) (e.g., `feat:`, `fix:`, `docs:`)

## Reporting Issues

- Use the [GitHub Issues](https://github.com/rizafahmi/clawdex/issues) page
- Include your Elixir/OTP version (`elixir --version`)
- Provide steps to reproduce the issue

## Code of Conduct

Be kind and respectful. We're all here to build something useful together.
