# ZigZag Architecture Overview  

This document provides a detailed overview of the folder structure and purpose of each module in the **ZigZag** codebase. It is intended for contributors and developers to understand the organization and responsibilities of each component.  

---

## Folder Structure  

### `src/` – All source code  

- **`assets/`** – Static assets (images, icons, files used for documentation or GitHub).  
- **`benchmarks/`** – TODO: Add benchmarking scripts and performance tests.  
- **`cache/`** – Source code for caching system to speed up repeated operations.  
- **`utils/`** – Utilities used across the project.  

### CLI Domain  

- **`cli/`** – CLI-specific logic.  
  - **`cli/commands/`** – Definitions for all available CLI commands and their flag options.  
  - **`cli/handlers/`** – Handlers for CLI flags and configuration options, processing user input.  

### Configuration  

- **`conf/`** – Contains configuration files.  
  - `zig.conf.json` – Default configuration file for ZigZag.  

### Filesystem Abstraction  

- **`fs/`** – Code for interacting with the operating system’s filesystem.  
  - **`fs/mmap/`** – Memory-mapped file implementations.  
    - **`fs/mmap/unix/`** – Unix-specific memory-mapped file logic.  
    - **`fs/mmap/windows/`** – Windows-specific memory-mapped file logic.  
  - **`fs/watcher/`** – Watcher implementations for monitoring filesystem changes across different OSes.  

### Jobs & Workers  

- **`jobs/`** – Individual jobs for file processing tasks.  
- **`walker/`** – File walker that orchestrates jobs to perform operations across directories and files.  
- **`workers/`** – Implements concurrency, enabling parallel execution of tasks across multiple threads or processes.  

### Platform-Specific Logic  

- **`platform/`** – Platform-specific code for different operating systems.  
  - **`platform/windows/`** – Windows-specific implementations.  

### Templates & Dashboard  

- **`templates/`** – HTML templating and TypeScript source code for generating the dashboard.  
  - **`templates/src/`** – TypeScript, CSS, and HTML source code for the templates.  

---

## Summary  

ZigZag’s architecture is modular and organized around **domains of responsibility**:  

- **CLI**: Handles user input and commands.  
- **Filesystem**: Abstracts OS-specific file operations and watchers.  
- **Jobs & Workers**: Provides a structured system for processing files efficiently, including concurrency.  
- **Platform**: Houses platform-specific logic.  
- **Templates**: Contains the front-end dashboard code for visual reports.  
- **Cache**: Maintains performance optimizations for repeated operations.  
- **Utils**: Provides utility functions used across the project.  

This structure makes the project **scalable, maintainable, and easy to extend** for new platforms, jobs, or features.
