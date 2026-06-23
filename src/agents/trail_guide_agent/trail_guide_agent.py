
"""
Trail Guide Agent — deployment script.
Reads system instructions from a versioned prompt file and creates/updates the agent in Foundry.
Each run creates a NEW version of the agent in Foundry (Foundry auto-versions).
"""
import os
import argparse
from azure.ai.projects import AIProjectClient
from azure.ai.agents.models import Agent
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv()

# Parse which prompt version to deploy
parser = argparse.ArgumentParser()
parser.add_argument("--prompt-file", required=True, help="Path to prompt .txt file")
args = parser.parse_args()

# Read prompt content
with open(args.prompt_file, "r") as f:
    instructions = f.read().strip()

# Connect to Foundry project
project_client = AIProjectClient(
    endpoint=os.environ["PROJECT_ENDPOINT"],
    credential=DefaultAzureCredential()
)

# Create / update agent — Foundry auto-creates a new version
agent = project_client.agents.create_agent(model=os.environ.get("MODEL_NAME", "gpt-4.1-mini"),
                                           name=os.environ.get("AGENT_NAME", "trail-guide"),
                                           instructions=instructions,
                                           description="Trail Guide assistant — versioned via GitHub")

print(f"✅ Agent deployed")
print(f"   ID: {agent.id}")
print(f"   Name: {agent.name}")
print(f"   Prompt source: {args.prompt_file}")
