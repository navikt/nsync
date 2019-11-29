1
echo ${CLUSTER_NAME}
nohup sh -c '( ( ./uptimed.sh https://up.dev-fss.nais.io/ping 600 ) & echo $! > pid )' > ./nohup.out

2
sh ./check_uptimed.sh