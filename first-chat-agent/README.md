# Your First AI Agent in Python

Welcome to the exciting world of AI! This guide will walk you through creating a simple, command-based AI agent using Python. This agent will be able to understand a few basic commands and respond to them.

## What is an AI Agent?

At its core, an AI agent is a program that can perceive its environment and take actions to achieve specific goals. Our simple agent's "environment" will be the text you type, and its "actions" will be the text it prints in response.

We will build a basic "reflex agent," which means it reacts to what it perceives without remembering past interactions.

## Prerequisites

Before you start, make sure you have Python installed on your computer. You can download it from [python.org](https://www.python.org/).

You will also need to install one library, `colorama`, which will make our agent's output look a bit nicer in the terminal.

## How to Run Your Agent

1.  **Set up your project:**
    * Create a new folder for your project.
    * Save the `agent.py` and `requirements.txt` files into this new folder.

2.  **Open your terminal or command prompt:**
    * Navigate to the folder you just created. For example:
        ```bash
        cd path/to/your/project
        ```

3.  **Install the necessary library:**
    * Run the following command to install `colorama`:
        ```bash
        pip install -r requirements.txt
        ```

4.  **Run the agent:**
    * Execute the Python script with this command:
        ```bash
        python agent.py
        ```

5.  **Interact with your agent:**
    * The agent will prompt you to enter a command. Try typing `hello`, `time`, `date`, or `exit`.

## Understanding the Code (`agent.py`)

The `agent.py` script has a few key parts:

* **`AIAgent` class:** This is the blueprint for our agent.
    * The `__init__` method is the constructor. It initializes the agent's state (in this case, just giving it a name).
    * The `perceive_and_act` method is the core of the agent. It takes your input, decides what to do, and returns a response. This is where the agent's "intelligence" lies.
* **The main loop:** The `if __name__ == "__main__":` block is what runs when you execute the script. It creates an instance of our agent and keeps it running, waiting for your input until you type `exit`.

This is a very simple starting point, but it covers the fundamental concepts of an agent: perceiving input and acting upon it. From here, you can expand its capabilities, give it memory, or connect it to other tools and APIs!
