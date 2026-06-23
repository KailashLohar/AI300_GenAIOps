# GenAIOps Agent Repository

            Versioned prompts and deployment scripts for Microsoft Foundry agents.
            
            ## Setup
            1. Copy `.env.example` to `.env` and fill in values
            2. `pip install -r requirements.txt`
            3. `az login`
            
            ## Deploy a version
            ```
            cd src/agents/trail_guide_agent
            python trail_guide_agent.py --prompt-file prompts/v1_instructions.txt
            ```
            
            ## Versioning
            - Each prompt file (`v1_instructions.txt`, `v2_instructions.txt`, ...) corresponds to a Foundry agent version
            - Tag releases with Git: `git tag v1`, `git tag v2`