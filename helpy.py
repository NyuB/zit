import zlib
import sys

def main(args: list[str]):
    if args[1] == "decompress":
        with open(args[2], 'rb') as file:
            content = file.read()
            inflated = zlib.decompress(content)
            print(inflated)
    elif args[1] == "compress":
        with open(args[2], 'rb') as file:
            content = file.read()
            deflated = zlib.compress(content)
            if(len(args) > 3):
                with open(args[3], 'wb') as out:
                    out.write(deflated)
            else:
                print(deflated)
    elif args[1] == "adler32":
        print(zlib.adler32(args[2].encode(encoding = "charmap")))
    elif args[1] == "ord":
        print(ord(args[2][0]))
    elif args[1] == "chr":
        print(chr(int(args[2])))
    elif args[1] == "hex":
        print(hex(int(args[2])))
if __name__ == '__main__':
    main(sys.argv)
