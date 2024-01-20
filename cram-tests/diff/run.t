Setup
  $ EXEC=${EXEC:-"${TESTDIR}/../../bin/tools"}

Usage
  $ ${EXEC} help
  Usage: tools {diff, hash, help,} [args ...]
  
      diff <file_a> <file_b>: output the edit script to update from file_a from file_b
  
      hash <file>           : output the hexadecimal representation of the sha1 checksum of file 
  
      help                  : print this help message

Diff two files
  $ ${EXEC} diff ${TESTDIR}/a.txt ${TESTDIR}/b.txt 
  2 - SWAP 1
  2 + SWAP 2
  5 - SWAP 2
  5 + SWAP 1

