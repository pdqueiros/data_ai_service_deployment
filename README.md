# Service deployment

The repository contains the bash files useful for deploying and update services in production.

## Smart Web Reader

### Setup of server

For Azure, manually launch the commands in *SETUP_azure.sh*

Then

```bash
bash smart_web_reader/copy_common_files.sh
bash smart_web_reader/copy_custom_files.sh

bash smart_web_reader/execute_step_remotely.sh  # INFRA_launch.sh


# if tests:
# Copy docker-compose-dev.yaml
# ```docker compose -f docker-compose-dev.yaml up --build -d```

bash smart_web_reader/execute_step_remotely.sh  # SWR_launch.sh
```

### Tests
on local machine
```bash
export MONGO_HOST=t-gis-001.elinkapp.com  # staging server hostname
python src/smart_web_reader/common/jobs/submit_job.py
```


### Update

```bash
bash smart_web_reader/execute_step_remotely.sh  # stop
bash smart_web_reader/execute_step_remotely.sh  # update
bash smart_web_reader/execute_step_remotely.sh  # launch
```
