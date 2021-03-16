import { listRunners, createRunner } from './runners';
import { createOctoClient, createGithubAuth } from './gh-auth';
import yn from 'yn';

export interface ActionRequestMessage {
  id: number;
  eventType: string;
  repositoryName: string;
  repositoryOwner: string;
  installationId: number;
}

export const scaleUp = async (eventSource: string, payload: ActionRequestMessage): Promise<void> => {
  console.info("hello world 1");
  if (eventSource !== 'aws:sqs') throw Error('Cannot handle non-SQS events!');
  const enableOrgLevel = yn(process.env.ENABLE_ORGANIZATION_RUNNERS, { default: true });
  const maximumRunners = parseInt(process.env.RUNNERS_MAXIMUM_COUNT || '3');
  const runnerExtraLabels = process.env.RUNNER_EXTRA_LABELS;
  const runnerGroup = process.env.RUNNER_GROUP_NAME;
  const environment = process.env.ENVIRONMENT as string;
  const ghesBaseUrl = process.env.GHES_URL as string;

  let ghesApiUrl = '';
  if (ghesBaseUrl) {
    ghesApiUrl = `${ghesBaseUrl}/api/v3`;
  }
  console.info(ghesApiUrl);
  console.info("enable org level");
  console.info(enableOrgLevel);
  let installationId = payload.installationId;
  if (installationId == 0) {
    const ghAuth = await createGithubAuth(undefined, 'app', ghesApiUrl);
    const githubClient = await createOctoClient(ghAuth.token, ghesApiUrl);
    installationId = enableOrgLevel
      ? (
          await githubClient.apps.getOrgInstallation({
            org: payload.repositoryOwner,
          })
        ).data.id
      : (
          await githubClient.apps.getRepoInstallation({
            owner: payload.repositoryOwner,
            repo: payload.repositoryName,
          })
        ).data.id;
  }


  const ghAuth = await createGithubAuth(installationId, 'installation', ghesApiUrl);
  const githubInstallationClient = await createOctoClient(ghAuth.token, ghesApiUrl);
  const checkRun = await githubInstallationClient.checks.get({
    check_run_id: payload.id,
    owner: payload.repositoryOwner,
    repo: payload.repositoryName,
  });

  console.log("check run");
  console.log(checkRun);
  
  const repoName = enableOrgLevel ? undefined : `${payload.repositoryOwner}/${payload.repositoryName}`;
  const orgName = enableOrgLevel ? payload.repositoryOwner : undefined;

  console.log(repoName);
  console.log(orgName);
  console.log(checkRun.data.status);
  console.log(checkRun);
  console.log(checkRun.data);
  console.log("-----------");
  if (checkRun.data.status === 'queued' || checkRun.data.status === 'completed' ) {
    const currentRunners = await listRunners({
      environment: environment,
      repoName: repoName,
    });
    console.info(
      `${enableOrgLevel
        ? `Organization ${payload.repositoryOwner}`
        : `Repo ${payload.repositoryOwner}/${payload.repositoryName}`
      } has ${currentRunners.length}/${maximumRunners} runners`,
    );

    if (currentRunners.length < maximumRunners) {
      // create token
      const registrationToken = enableOrgLevel
        ? await githubInstallationClient.actions.createRegistrationTokenForOrg({ org: payload.repositoryOwner })
        : await githubInstallationClient.actions.createRegistrationTokenForRepo({
          owner: payload.repositoryOwner,
          repo: payload.repositoryName,
        });
      const token = registrationToken.data.token;

      const labelsArgument = runnerExtraLabels !== undefined ? `--labels ${runnerExtraLabels}` : '';
      const runnerGroupArgument = runnerGroup !== undefined ? ` --runnergroup ${runnerGroup}` : '';
      const configBaseUrl = ghesBaseUrl ? ghesBaseUrl : 'https://github.com';
      await createRunner({
        environment: environment,
        runnerConfig: enableOrgLevel
          ? `--url ${configBaseUrl}/${payload.repositoryOwner} --token ${token} ${labelsArgument}${runnerGroupArgument}`
          : `--url ${configBaseUrl}/${payload.repositoryOwner}/${payload.repositoryName} ` +
          `--token ${token} ${labelsArgument}`,
        orgName: orgName,
        repoName: repoName,
      });
    } else {
      console.info('No runner will be created, maximum number of runners reached.');
    }
  }
};
