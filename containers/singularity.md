## Convert Docker to singularity container 

Normaly it is enough to pass the location of the docker container to the
singularity command and the convertion is done on the fly

  singularity pull debian11.sif docker://debian/stable:latest (wrong)

Since the above command failed due to a wrong syntax another way for
convertion was searched. The project docker2singularity was found on GitLab
(https://github.com/singularityhub/docker2singularity) which does the
conversion inside a docker container and outputs the needed singularity
container. 

To convert an image the following command has to be executed

  docker run -v /var/run/docker.sock:/var/run/docker.sock  \
    -v /tmp/test:/output --privileged -t --rm \
    quay.io/singularity/docker2singularity \
    debian:11

which converts the debian 11 image from dockerhub into a corresponding
singularity image. 


The correct singularity command is

  singularity pull debian11.sif docker://debian:11 (correct)


