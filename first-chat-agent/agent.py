import os
import google.genai as genai
from colorama import Fore, Style, init
from dotenv import load_dotenv

# Initialize colorama
init(autoreset=True)

class AIAgent:
    """
    An LLM-powered AI Agent that uses Google's Gemini model for conversation.
    """
    def __init__(self, name="GenAI"):
        self.name = name
        self.client = None
        self.chat = None
        self._configure_llm()

    def _configure_llm(self):
        """
        Configures the connection to the Google Gemini model using an API key.
        """
        load_dotenv()
        api_key = os.getenv("GEMINI_API_KEY")

        if not api_key:
            print(f"{Fore.RED}Error: GEMINI_API_KEY not found. Please create a .env file and add it.")
            exit()

        self.client = genai.Client(api_key=api_key)
        self.chat = self.client.chats.create(model='models/gemini-2.5-flash')
        print(f"{Fore.GREEN}LLM configured successfully!")

    def perceive_and_act(self, user_input):
        """
        Sends the user's input to the LLM and returns the response.
        The complex logic is now handled by the Gemini model.
        """
        if not self.chat:
            return f"{Fore.RED}Error: The chat model is not configured."

        try:
            # Send message to the model and get the response
            response = self.chat.send_message(user_input)
            return response.text
        except Exception as e:
            return f"{Fore.RED}An error occurred while communicating with the LLM: {e}"

def main():
    """
    The main function to run the AI agent.
    """
    my_agent = AIAgent(name="GeminiBot")

    print(f"{Fore.MAGENTA}{Style.BRIGHT}AI Agent '{my_agent.name}' is online. Type 'exit' or 'quit' to end.")

    while True:
        try:
            user_input = input(f"{Style.BRIGHT}You: ")
            
            if user_input.lower().strip() in ["exit", "quit"]:
                print(f"\n{Style.BRIGHT}{my_agent.name}: {Fore.YELLOW}Goodbye!")
                break
            
            response = my_agent.perceive_and_act(user_input)
            print(f"{Style.BRIGHT}{my_agent.name}: {Fore.CYAN}{response}")

        except KeyboardInterrupt:
            print(f"\n{Style.BRIGHT}{my_agent.name}: {Fore.YELLOW}Shutdown initiated. Goodbye!")
            break

if __name__ == "__main__":
    main()