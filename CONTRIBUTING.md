# Contributing

Thanks for your interest in improving this template! Here's how to get involved.

## How to Contribute

1. **Fork** the repository
2. **Create a branch** for your feature or fix: `git checkout -b feature/your-feature`
3. **Make your changes** and test them locally
4. **Commit** with a clear message: `git commit -m "Add: your feature description"`
5. **Push** to your fork: `git push origin feature/your-feature`
6. **Open a Pull Request** against `main`

## What to Contribute

- Bug fixes in `setup.sh` or Docker configuration
- Improved documentation
- New setup.sh commands or flags
- Docker Compose optimizations
- Support for additional package managers or frameworks

## Guidelines

- Keep `setup.sh` simple and readable
- Test your changes with a clean run: `./setup.sh --reset client && ./setup.sh --dev docker up`
- Update `README.md` if you add or change commands
- Follow existing code style and conventions

## Reporting Issues

Open an [issue](../../issues) with:
- A clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- Your OS and Docker version

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
