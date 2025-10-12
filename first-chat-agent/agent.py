import datetime
from colorama import Fore, Style, init

# Initialize colorama to work on all platforms
init(autoreset=True)

class AIAgent:
    """
    A simple AI Agent that can perceive text commands and act on them.
    """
    def __init__(self, name="Agent"):
        """
        Initializes the agent with a name.
        """
        self.name = name

    def perceive_and_act(self, user_input):
        """
        This is the core function of the agent.
        It takes the user's input, processes it, and returns a response.
        """
        # Normalize the input to lowercase to make it case-insensitive
        command = user_input.lower().strip()

        # Decision-making logic: Respond based on the command
        if command == "hello":
            return f"{Fore.GREEN}Hello! I am {self.name}. How can I help you?"
        elif command == "time":
            now = datetime.datetime.now()
            current_time = now.strftime("%I:%M:%S %p")
            return f"{Fore.CYAN}The current time is {current_time}."
        elif command == "date":
            today = datetime.date.today()
            return f"{Fore.CYAN}Today's date is {today.strftime('%B %d, %Y')}."
        elif command == "exit":
            return f"{Fore.YELLOW}Goodbye! Shutting down."
        else:
            return f"{Fore.RED}Sorry, I don't understand the command: '{user_input}'"

def main():
    """
    The main function to run the AI agent.
    """
    # Create an instance of our agent
    my_agent = AIAgent(name="EchoBot")

    print(f"{Fore.MAGENTA}{Style.BRIGHT}AI Agent '{my_agent.name}' is online. Type 'exit' to quit.")

    # Main loop to keep the agent running
    while True:
        try:
            # Get input from the user
            user_input = input(f"{Style.BRIGHT}You: ")

            # The agent perceives the input and decides on an action
            response = my_agent.perceive_and_act(user_input)

            # Print the agent's response
            print(f"{Style.BRIGHT}{my_agent.name}: {response}")

            # Check if the user wants to exit
            if user_input.lower().strip() == "exit":
                break
        except KeyboardInterrupt:
            print(f"\n{Style.BRIGHT}{my_agent.name}: {Fore.YELLOW}Shutdown initiated by user. Goodbye!")
            break


if __name__ == "__main__":
    main()