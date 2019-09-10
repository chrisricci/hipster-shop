# Anthos Developer Demo with Hipster Shop and Binary Authorization and Vulnerability Scanning

We use [Hipster Shop app](https://github.com/GoogleCloudPlatform/microservices-demo) as the basis for this demo
. Key elements used and showcased in this demo are the following:

- Skaffold (Open Source tool to simplify k8s app development)
- Google Cloud Code (IDE plugin with support for Skaffold and built-in GCP productivity tools)
- GKE (managed k8s on GCP)
- Google Cloud Build (GCP managed service to run scalable builds in the cloud)
- Google Container Vulnerability Scanning (checks your images for CVEs and reports on it)
- Google Container Binary Authorization (allows one to provide digital signatures for images and block deployment if
 needed)
- Google Container Registry (GCP managed service for storing and managing images)
- GitHub integration with Cloud Build (triggers builds on merge)
- Docker for Desktop with Kubernetes for Docker (used to show local development)

This document describes flow of the demo and steps to set it up and run it.

## Preparation and setup

In order to show the demo we need to setup the following:

- Environment on the development laptop
- Environment on GCP

Both of these are setup from within the same script.

### Setup on your development laptop

These instructions below can be run on MacOS, Linux, CloudShell or GCE VM as you dev machine.

1. Install Docker and local Kubernetes. We recommend Docker for Desktop (Mac/Windows): It provides Kubernetes
 support as [noted here](https://docs.docker.com/docker-for-mac/kubernetes/). On your dev machine launch 
 “Docker for Desktop”. Go to Preferences:

   - choose “Enable Kubernetes”,
   - set CPUs to at least 3, and Memory to at least 6.0 GiB
   - on the "Disk" tab, set at least 32 GB disk space
   
   Make sure you have a local instance of Docker daemon running (Docker Desktop or other).
   
1. On your dev machine, go to your home directory and clone the 'hipster' repo into 'hipster-shop' directory:

    ```sh
    cd ~
    gcloud source repos clone hipster hipster-shop --project=cr-demo-project
    ```   

1. Before we can create a new project, we shall update the billing account id to your own. Open Google Cloud Console
 and find out what is [your billing account ID](https://pantheon.corp.google.com/billing/00199B-DAB963-FE83DD/manage?organizationId=433637338589).
 
1. Update file `setenv-local.sh` variable `BILLING_ACCOUNT_ID` with the value of your Billing Account ID.

1. This step will install additional local tools (GCloud SDK, kubectl, skaffold) as well
as provision and configure GCP environment (new project, new cluster, etc.):

   ```sh
   cd hipster-shop
   ./setup.sh [your-new-project-id]
   ```    

1. Make sure your deployment target is set to point to GKE cluster by updating file `setenv-local.sh` variable
 `DEPLOY_TARGET` to set it to the value of `${GKE_DEPLOY}`.
      
 1. Now we can deploy Hipster-Shop application into GKE. Note that for this step we are bypassing binary
 authentication and vulnerability scanning and deploying directly into GKE using skaffold. 

   ```sh
   ./skaffold.sh run
   ```    

1. Test your new Hipster-Shop app running on GKE cluster. Open GCP console, click on GKE services and click on Frontend
 service external URL and make sure your application functions properly.
 
1. Setup Binary Authorization for your GKE cluster:

    ```sh
    ./setup-binauth.sh
    ``` 
 
1. Time to deploy local development cluster. Change deployment target to your local dev cluster on your machine by
 updating `setenv-local.sh` variable `DEPLOY_TARGET=${LOCAL_DEPLOY}`
 
1. Deploy the app into your local cluster:

    ```sh
    ./skaffold.sh dev
    ``` 
   Note: If you need to cleanup the deployment (local or GKE, simply run `./skaffold.sh delete`)
   
1. Test local application. In your browser go to the url: http://localhost and make sure everything works as expected.  
 
### Demonstration flow

1. Tell the audience about the Hipster-Shop application, how it is built and show an (architecture diagram from
 GitHub)[https://github.com/GoogleCloudPlatform/microservices-demo] 
 
1. Show Hipster app running on GKE and explain that marketing wants to change number of recommendations from 1
 to 3 (or let audience pick the number between 2-4)
 
1. Show that we already have a running instance locally (see skaffold dev above) by opening a browser on http
://localhost

1.   
 
 
 ................
 ...........
 Presenter shows web app for Hipster Shop app - and says that we want to reduce the number of product recommendations
 We use local development using Cloud Code on local workstation - getting fast feedback loop locally and not having to deploy remotely (skaffold). Cloud Code provides easy creation of YAML files - templates and CICD integration
 TODO - decide what IDE to use??? (IntelliJ or something else?)
 TODO - what do we want to show in Cloud Code?
 With skaffold automatically make changes appear in local dev container in local k8s
 Once the bug is fixed and tested locally, we push code into GitHub
 New commit/merge starts Cloud Build
 TODO - better understanding of cloud build branching/conditionals
 TODO - understand github integration on change. Meaning can we limit what's built on a small change.
 Presenter opens Cloud Console and shows log output from ongoing Cloud Build
 Our build will pass OK
 we show the bad binary auth results in the past runs
 Result of the build (Image) is stored in the Container Registry 
 Vulnerability Scan gets triggered to validate the image
 The image is found to have vulnerabilities, so we send feedback back to developer to review
 TODO - how do we notify developer about the fail in vulnerability scan??
 Once resolved, the app gets deployed into test environment GKE on GCP
 Once the app is running, use Web App scanning of the app to detect security issues
 If all goes well, deploy into GKE production by merging into release branch
 During GKE deployment, the Binary Auth checks the image - show a positive check
 (optional Show canary deployment
 (optional) In a future version of the demo deploy into GKE-on-prem
 ............
 .............

1. Run `kubectl get nodes` to verify you're connected to “Kubernetes on Docker”.

1. Run `skaffold run` (first time will be slow, it can take ~20 minutes).
   This will build and deploy the application. If you need to rebuild the images
   automatically as you refactor the code, run `skaffold dev` command.

1. Run `kubectl get pods` to verify the Pods are ready and running. The
   application frontend should be available at http://localhost:80 on your
   machine.
   
## Cleanup

The easiest way to remove all resources is to delete the entire GCP project. However if you prefer to delete GKE
 cluster, simply run:
 
```sh
cd ~/hipster-shop
./skaffold.sh delete
```

In order to remove Binary Authentication and Vulnerability Scanning, run: 

```sh
./cleanup-binauth.sh
```
