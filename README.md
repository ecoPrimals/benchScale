# benchScale — Boot Cycle Testing

## Wave 233 Reboot Plan

### Boot Chain
```
GAIA Boot Engine (5s timeout)
  ├─ [DEFAULT] Windows Boot Manager
  ├─ Smokeless UMAF — Read CBS/NBIO offsets  
  ├─ modGRUBShell — Write UEFI variables
  └─ Reboot / Shutdown
```

### NVMe Prescription
- Samsung 4TB: Root port 0B OK, controller Unknown (link training fail)
- WD BLACK 4TB: Root port 0C Unknown (firmware disabled)
- Fix: AMD CBS → NBIO → PCIe → M.2 slot enable

### CPU Prescription  
- 8C/8T visible, ACPI has 32 entries (16C/32T available)
- Fix: AMD CBS → CCD0+CCD1 enable, SMT enable

### Verification Script
`scripts/reboot-cycle.ps1 -Phase post`
