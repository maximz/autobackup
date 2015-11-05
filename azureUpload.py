#!/usr/bin/python

# @author: Maxim Zaslavsky
# uploads list of files to azure blob storage. pass absolute file paths in through stdin
# see usage and installation instructions at https://github.com/maximz/autobackup


# To configure, read:
# http://blogs.msdn.com/b/tconte/archive/2013/04/17/how-to-interact-with-windows-azure-blob-storage-from-linux-using-python.aspx
# export AZURE_STORAGE_ACCOUNT=tcontepub
# export AZURE_STORAGE_ACCESS_KEY='secret key'

# Open issue: https://github.com/Azure/azure-sdk-for-python/issues/264


# specify storage container name here (will be created if doesn't exist)
storage_container_name = 'quantabackups'

# verify MD5 on upload?
verify_md5 = False #True # disabled because of the open issue


# get file paths to upload
import sys
paths = sys.stdin.readlines()
paths = [p.strip() for p in paths] # strip \n's

print 'uploading', len(paths), 'files'


# setup azure connection
from azure.storage import BlobService
blob_service = BlobService()
# make sure container exists
blob_service.create_container(storage_container_name) # can't use underscores    

# helper methods for upload:
# file names from path
import ntpath
def path_leaf(path):
    # http://stackoverflow.com/a/8384788/130164
    head, tail = ntpath.split(path)
    return tail or ntpath.basename(head)    
# md5 generation for validating uploads
import hashlib
def md5_for_file(f, block_size=2**20):
    md5 = hashlib.md5()
    while True:
        data = f.read(block_size)
        if not data:
            break
        md5.update(data)
    return md5.digest().encode('base64')[:-1] # hexdigest()
    # this is the format that azure stores its md5's in
    # len(_) = 24
    
# do the uploads
for p in paths:
    blob_name = path_leaf(p)
    if verify_md5:
        original_md5 = md5_for_file(open(p, 'rb'))
        blob_service.put_block_blob_from_path(storage_container_name, blob_name, p, content_md5=original_md5) # specify md5 to do an md5 check automatically
        # serverside_md5 = blob_service.get_blob_properties(storage_container_name, blob_name)['content-md5'] # get md5 of uploaded blob
        # see https://github.com/Azure/azure-sdk-for-python/blob/master/azure/storage/blobservice.py
    else:
        blob_service.put_block_blob_from_path(storage_container_name, blob_name, p)

print 'uploaded'
