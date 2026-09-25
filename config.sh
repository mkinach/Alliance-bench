UNAME="<user>"                                    # name of the user
CLUSTER="<host>"                  # name of the cluster
HOST="${UNAME}@${CLUSTER}"
RSSH="ssh -i $HOME/.ssh/id_rsa"                    # SSH key for connecting to the cluster
MIRROR="./mirror"                                  # mirror location
PROJECT="projects/def-sponsor00/${UNAME}"          # the user's project space
EXCLUDES="--exclude=/projects --exclude=/nearline" # cluster dirs to exclude from mirror

# custom text to append to each prompt.md
SUFFIX=""
#SUFFIX="Documentation on how to use this cluster is provided in /cvmfs/soft.computecanada.ca/custom/docs"
#SUFFIX="Documentation on how to use this cluster is provided via your alliance-docs skill, as well as your alliance-slurm and alliance-cvmfs skills"
