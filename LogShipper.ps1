#################################
### Filename  : LogShipper.ps1
### Version   : 1.02
### Date      : 10/7/2014
### Author    : Alucas
#################################

#########################################################################################################################
############################################## PROCESS BREAKDOWN ########################################################
#########################################################################################################################
# Step 1. Find files older than a day by exluding files matching current date in yyMMdd format in filename              #
# Step 2. 7zip log files from .log to .zip with _# in name. This # is pulled from Hostname. ex: Production###           #
# Step 3. Verify .zip file with 7zip, if it can not verify it will log this and email out a alert                       #
# Step 4. If cleanup is enabled it will delete .log files that were zipped up. (enabled with $Cleanup = 1)              #
# Step 5. Look for zip files in $filepath, create list for sftp                                                         #
# Step 6. Upload files with SFTP to $sftpPath\ORIGINALname_#.zip on $sftpServer (sftpPath is pulled from hostname #)    # 
# Step 7. Verify file is uploaded and delete local .zip file. If upload has failed, Send email alert and note in log.   # 
#########################################################################################################################
############################################## PROCESS BREAKDOWN ########################################################
#########################################################################################################################
#
########################
#### User Variables ####
########################
# Compression Settings
$filePath = "E:\Logfiles\" # Filepath (note this is recursive)
$Cleanup = "1" # Change this to 1 to activate cleanup of uncompressed log files
#SFTP Settings
$sftpUser = "Logshipperusername"
$sftpPass = "examplepassword"
$sftpServer = "128.0.0.1 (Replace with SFTP server)"
$sftpstring = "$sftpUser@$sftpServer"

##################################
##### END USER CONFIG OPTIONS ####
##################################
# Resources
$basedir = "C:\Scripts\LogShipper"
# Debug log
$debuglog = ($basedir + "\log.txt")
# Bin resource file check
if (-not (test-path ($basedir + "\bin\7za.exe"))) {throw "$env:$basedir + \bin\7za needed"} 
if (-not (test-path ($basedir + "\bin\psftp.exe"))) {throw "$env:$basedir + \bin\psftp.exe needed"}
# Alias for 7-zip 
set-alias sz ($basedir + "\bin\7za.exe") 
$psftp = ($basedir + "\bin\psftp.exe")

# Compression 
$sn = (gc env:computername) -Replace '^Production(\d+)$','$1'  # Production Server Number
$datefind = (get-date -f yyMMdd)

# Choose folder mapping depending on cluster (pulled from hostname #)
If($sn -eq "1" -or 
   $sn -eq "2"){        # WEB1 CLUSTER
   $sftpPath = "/"
   }
If($sn -eq "3" -or 
   $sn -eq "4"){        # WEB2 CLUSTER
   $sftpPath = "WEB2/"
   }
If ($sn -eq "5" -or 
    $sn -eq "6" -or 
    $sn -eq "7" -or 
    $sn -eq "8" -or     # WEB3 CLUSTER
    $sn -eq "9" -or 
    $sn -eq "10" -or
    $sn -eq "11" -or
    $sn -eq "12" -or
    $sn -eq "13" -or
    $sn -eq "14" -or
    $sn -eq "15"){
   $sftpPath = "WEB3/"
   } 
# SFTP 
$sftpuploadlist = ($basedir + "\Fileupload.txt")
$sftpscriptfile = ($basedir + "\psftp")

# SMTP
$ErrorsExist = "0"
$ServerName = gc env:computername
$SmtpClient = new-object system.net.mail.smtpClient
$MailMessage = New-Object system.net.mail.mailmessage
$MailMessage.Body = ""
$MailMessage.Subject = $ServerName +" Log-Shipper Job Failed"
$MailMessage.from = ($ServerName + "@example.com")
# SMTP Settings
$SmtpClient.Host = "128.0.0.1 (replace with SMTP server)"
$MailMessage.To.add("infrastructureTeam@example.com")

## Kill old debuglog and  recreate new
if (Test-Path $debuglog) { Remove-Item $debuglog }
### Compress IIS logfiles older than a day and cleanup

 # Find files with .log older than a day
$filefilter = Get-ChildItem -Recurse -Path $filePath | Where-Object {$_.extension -eq ".log" -and ($_.Name -NotMatch $datefind)} # Find files in this path that are .log and less than a day old.
# Process those files and zip them up
foreach ($file in $filefilter) { 
          if ($file -ne $null){               
                    $name = $file.name 
                    $directory = $file.DirectoryName 
                    $zipfile = $name.Replace(".log","_$sn.zip")                                  
                    sz a -tzip "$directory\$zipfile" "$directory\$name" 
                    sz t "$directory\$zipfile"
    
                    if($LASTEXITCODE -eq 0){
                         "Logfile $name has been compressed successfully" | Add-Content $debuglog -Encoding Ascii
                            # If Cleanup is enabled, then verify that they are compressed and then delete them.
                              if($Cleanup -eq 1){ 
                               Remove-Item "$directory\$name"
                                "Logfile $name has been compressed and the original has been deleted" | Add-Content $debuglog -Encoding Ascii
                                } else { 
                                "Logfile $name was not deleted. Cleanup not turned on" | Add-Content $debuglog -Encoding Ascii
                                }  
                    } else {
                    "Logfile $name has not been compressed. Can not do cleanup" | Add-Content $debuglog -Encoding Ascii
                    $ErrorsExist = "1"
                    Exit
                    } 
  
           } else {
           "No logs to Compress" | Add-content $debuglog -Encoding Ascii                 
           }
}
### SFTP Logs to urchin        
            
# Create list for PSFTP to grab and upload
$uploadlist = Get-ChildItem -Recurse -Path $filePath | Where-Object {$_.extension -eq ".zip"}
foreach ($file in $uploadlist) {
 if ($file -ne $null){ 
               $uploadfilename = $file.name
               $fullpath = $file.FullName
               $uploadpath = $file.DirectoryName
               $uploadfolder = $file.DirectoryName.Replace("$filepath","") 
          If (Test-Path $sftpscriptfile){Remove-Item $sftpscriptfile}
                 
             $sftpScriptFile
             "cd ""$sftpPath$uploadfolder""" | Set-Content $sftpscriptfile -Encoding Ascii
             "lcd ""$uploadpath""" | Add-Content $sftpscriptfile -Encoding Ascii
             "put ""$uploadfilename""" | Add-content $sftpscriptfile -Encoding Ascii 
             "quit" | Add-Content $sftpscriptfile -Encoding Ascii
             $ExecSftpScriptFile = "y" | & $psftp $sftpstring -pw $sftpPass -b $sftpScriptFile 
             $ExecSftpScriptFile
             
        if ($LASTEXITCODE -eq 0){
            "File Upload Success for $uploadfilename" | Add-Content $debuglog -Encoding Ascii
                If ($ErrorsExist -eq 0){
                 Remove-Item "$uploadpath\$uploadfilename" 
                 "Zipfile $uploadfilename zipfile has been deleted from $ServerName" | Add-Content $debuglog -Encoding Ascii
                }
       }
        Else {
            "File Upload Failed for $uploadfilename" | Add-Content $debuglog -Encoding Ascii
             $ErrorsExist = "1"
            }
        
 } Else { 
   "No Files to Upload" | Add-Content $debuglog -Encoding Ascii
 }           
}
If ($ErrorsExist -eq 1){
 $MailMessage.Body += (Get-Content $debuglog | out-string)
    $SmtpClient.Send($MailMessage)
    } Else {
    "Logshipper completed successfully with no errors!" | Add-Content $debuglog -Encoding Ascii
}