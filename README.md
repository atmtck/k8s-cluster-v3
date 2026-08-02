### Sistema di installazione per cluster k8s bare-metal, su minipc Chuwi Herobox

#### Preparazione:
- preparare un disco usb Debian live
- creare una partizione aggiuntiva sul disco usb, clonarci questa repo
- creare e compilare *cluster_config.csv* con i campi del file di esempio
- eseguire *cfgmake.sh* per creare i file con le variabili per ogni host

#### Installazione:
- accendere il pc e entrare nell utility configurazione BIOS
- modificare le impostazioni:
  ```
  Security > Secure Boot > Key Management > Factory Key Provision [Disabled]
  Advanced > Trusted Computing > Pending Operation [TPM Clear]
  Advanced > Thunderbolt(TM) Configuration > PCIE Tunnelling over USB4 [Disabled]
  Advanced > Thunderbolt(TM) Configuration > Integrate Thunderbolt(TM) Support [Disabled]
  Advanced > USB Configuration > Legacy USB Support [Disabled]
  Advanced > USB Configuration > XHCI Hand-off [Disabled]
  Chipset > PCH-IO Configuration > HD Audio Configuration > HD Audio [Disabled]
  Boot > Fast Boot > NVME Support [Disabled]
  Boot > Fast Boot > PS2 Devices Support [Disabled]
  Boot > Oem Entend Setup Configuration > Auto Power On [Enabled]
  Boot > Oem Entend Setup Configuration > Wake On Lan [Disabled]
  ```
- salvare, riavviare e rientrare nel BIOS
- impostare secure boot in modalità setup:
  ```
  Security > Secure Boot > Reset To Setup Mode
  ```
- riavviare come richiesto, al reboot fare boot dal disco usb Debian
- avviare l'istanza Debian live, verificare connettività internet
- aprire la cartella con la repository configurata, ed eseguire *debootstrap.sh*
- spegnere il pc a esecuzione terminata

#### Finalizzazione
- al primo primo avvio, entrare nel bios, verificare stato secure boot, e riabilitarlo
- accedere alla nuova installazione, registrare le chiavi LUKS sel TPM con `/usr/local/bin/tpm2-enroll-sb-keys`
