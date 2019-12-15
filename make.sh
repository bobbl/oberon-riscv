#!/bin/sh


help() {
    echo "Usage: $0 <targets> ..."
    echo "  all      Build oberon-riscv"
    echo "  help     This help"
    exit 1
}


here=$(pwd)
oberonc_bin=${here}/tools/oberonc/bin


all() {
    java -cp $oberonc_bin:. oberonc build src/ORS.Mod src/ORB.Mod src/ORG.Mod src/ORP.Mod
}




if [ $# -eq 0 ]
then
    help
fi


# Clone oberonc if not already done
if [ ! -d tools/oberonc ]
then
    mkdir -p tools
    cd tools
    git clone https://github.com/lboasso/oberonc.git
# Building not necessary, because it already contains compiled Java classes
#    cd oberonc
#    make build
#    cd ..

    # copy symbol files to 
    mkdir -p ../build
    cp Files.smb ../build
#    cp In.smb ../build
    cp Out.smb ../build
#    cp Strings.smb ../build
    cd ..
fi


while [ $# -ne 0 ]
do
    case $1 in
        help)
            help
            ;;
        all)
            all
            shift
            ;;
        *)
            echo "Unknown target $1. Stop."
            exit 2
            ;;
    esac
    shift
done
