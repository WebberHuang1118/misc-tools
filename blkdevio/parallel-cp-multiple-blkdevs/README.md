$ ./copy_and_verify.sh 10 b1 r1 b2 r2 b3 r3


$ docker build -t block-copy-check .

$ helm install block-copy ./block-copy