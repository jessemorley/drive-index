import React, { useState } from 'react';
import { 
  HardDrive, 
  File, 
  FileImage, 
  FileVideo, 
  FileAudio, 
  Settings, 
  Database, 
  Search, 
  ArrowUpDown,
  ChevronDown,
  Filter,
  CheckCircle2,
  AlertCircle
} from 'lucide-react';

export default function App() {
  // --- State & Data ---

  // 6 Indexed Drives
  const [drives, setDrives] = useState([
    { id: 1, name: 'Macintosh HD', size: '1 TB', used: '850 GB', type: 'NVMe', isBackup: false },
    { id: 2, name: 'Samsung T7', size: '2 TB', used: '1.2 TB', type: 'SSD', isBackup: false },
    { id: 3, name: 'LaCie Rugged', size: '4 TB', used: '3.8 TB', type: 'HDD', isBackup: true }, // Default backup
    { id: 4, name: 'SanDisk Extreme', size: '1 TB', used: '200 GB', type: 'SSD', isBackup: false },
    { id: 5, name: 'Archive Raid', size: '12 TB', used: '8.4 TB', type: 'RAID', isBackup: true }, // Default backup
    { id: 6, name: 'SD Backup', size: '256 GB', used: '120 GB', type: 'SD', isBackup: false },
  ]);

  // Duplicate Files Data
  const duplicates = [
    { 
      id: 101, 
      name: 'Project_Titan_Render_v04.mov', 
      size: '4.2 GB', 
      type: 'video', 
      drives: [1, 2, 5], 
      date: 'Oct 24, 2024' 
    },
    { 
      id: 102, 
      name: 'Q3_Financials_Final.pdf', 
      size: '14 MB', 
      type: 'doc', 
      drives: [1, 2], 
      date: 'Nov 01, 2024' 
    },
    { 
      id: 103, 
      name: 'IMG_8832_RAW.dng', 
      size: '85 MB', 
      type: 'image', 
      drives: [3, 5], 
      date: 'Sep 12, 2024' 
    },
    { 
      id: 104, 
      name: 'Backup_Catalog.db', 
      size: '1.1 GB', 
      type: 'db', 
      drives: [2, 3, 4, 6], 
      date: 'Aug 30, 2024' 
    },
    { 
      id: 105, 
      name: 'Podcast_Intro_Music.wav', 
      size: '120 MB', 
      type: 'audio', 
      drives: [1, 4], 
      date: 'Oct 15, 2024' 
    },
    { 
      id: 106, 
      name: 'unused_assets_folder.zip', 
      size: '3.5 GB', 
      type: 'zip', 
      drives: [3, 6], 
      date: 'Jul 22, 2024' 
    },
  ];

  const [hoveredFileId, setHoveredFileId] = useState(null);
  
  // Filter Toggles
  const [showBackedUp, setShowBackedUp] = useState(true);
  const [showDuplicates, setShowDuplicates] = useState(true); // Renamed for clarity

  // --- Logic ---

  const toggleBackup = (id) => {
    setDrives(drives.map(d => 
      d.id === id ? { ...d, isBackup: !d.isBackup } : d
    ));
  };

  // Check if a file has at least one copy on a backup drive
  const hasBackupCopy = (file) => {
     return file.drives.some(dId => drives.find(d => d.id === dId)?.isBackup);
  };

  // Filter the list based on toggles
  const filteredFiles = duplicates.filter(file => {
      const isBackedUp = hasBackupCopy(file);
      
      // Calculate if it acts as a "Duplicate" (redundant source files or no backup)
      const sourceDrives = file.drives.filter(dId => !drives.find(d => d.id === dId)?.isBackup);
      const hasRedundantSource = sourceDrives.length > 1;
      const isStrictlyUnsafe = !isBackedUp; // No backup at all
      
      // Condition A: Show if it matches "Backed Up" criteria
      if (showBackedUp && isBackedUp) return true;
      
      // Condition B: Show if it matches "Duplicates" criteria
      // This now includes backed up files IF they have multiple source copies (clutter)
      if (showDuplicates && (hasRedundantSource || isStrictlyUnsafe)) return true;

      return false;
  });

  const getHighlightStatus = (driveId) => {
    if (!hoveredFileId) return 'none';
    
    const file = duplicates.find(f => f.id === hoveredFileId);
    if (!file) return 'none';

    const hasFile = file.drives.includes(driveId);
    if (!hasFile) return 'dimmed'; // Dim drives that don't have the file

    const drive = drives.find(d => d.id === driveId);
    
    // New Logic: Check for single source + backup scenario
    const sourceDrivesWithFile = file.drives.filter(dId => {
        const d = drives.find(drv => drv.id === dId);
        return d && !d.isBackup;
    });
    const backupDrivesWithFile = file.drives.filter(dId => {
        const d = drives.find(drv => drv.id === dId);
        return d && d.isBackup;
    });

    if (sourceDrivesWithFile.length === 1 && backupDrivesWithFile.length >= 1) {
        if (!drive.isBackup) {
            return 'source-safe'; // This is the single source, highlight gray
        }
    }

    return drive.isBackup ? 'safe' : 'warning';
  };

  const getFileIcon = (type) => {
    switch(type) {
      case 'video': return <FileVideo size={20} className="text-purple-400" />;
      case 'image': return <FileImage size={20} className="text-blue-400" />;
      case 'audio': return <FileAudio size={20} className="text-pink-400" />;
      case 'db': return <Database size={20} className="text-slate-400" />;
      default: return <File size={20} className="text-gray-400" />;
    }
  };

  // --- Render ---

  return (
    <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-slate-900 to-slate-800 p-4 font-sans text-slate-200 selection:bg-blue-500/30">
      
      {/* App Window Container */}
      <div className="w-full max-w-5xl h-[85vh] min-h-[600px] bg-slate-900/80 backdrop-blur-2xl rounded-2xl border border-white/10 shadow-2xl flex flex-col overflow-hidden">
        
        {/* Title Bar (Global) */}
        <div className="h-10 border-b border-white/5 flex items-center px-4 bg-white/5 select-none shrink-0 z-20 justify-between">
          <div className="flex gap-2 w-20">
            <div className="w-3 h-3 rounded-full bg-red-500/80 hover:bg-red-500 transition-colors shadow-sm" />
            <div className="w-3 h-3 rounded-full bg-yellow-500/80 hover:bg-yellow-500 transition-colors shadow-sm" />
            <div className="w-3 h-3 rounded-full bg-green-500/80 hover:bg-green-500 transition-colors shadow-sm" />
          </div>
          <div className="font-medium text-sm text-slate-400/80 flex items-center justify-center gap-2">
             DriveIndex
          </div>
          <div className="w-20 text-right">
             <button className="text-slate-400 hover:text-slate-200 transition-colors">
                <Settings size={16} />
             </button>
          </div>
        </div>

        {/* Main Content Column (Sidebar removed) */}
        <div className="flex-1 flex flex-col overflow-hidden bg-slate-800/10">
        
            {/* Top Section: Drive Grid (Smaller padding) */}
            <div className="p-4 border-b border-white/5 relative z-10 shrink-0 bg-slate-900/10">
                <div className="flex justify-between items-end mb-3">
                    <div>
                        <h2 className="text-base font-semibold text-white">Indexed Drives</h2>
                        <p className="text-[10px] text-slate-500 mt-0.5">Toggle 'Backup' to configure safety logic.</p>
                    </div>
                    <div className="flex gap-4 text-[10px]">
                        <div className="flex items-center gap-1.5 text-orange-400">
                            <div className="w-1.5 h-1.5 rounded-full bg-orange-500 shadow-[0_0_8px_rgba(249,115,22,0.6)]" />
                            Duplicate
                        </div>
                        <div className="flex items-center gap-1.5 text-emerald-400">
                            <div className="w-1.5 h-1.5 rounded-full bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.6)]" />
                            Backup
                        </div>
                    </div>
                </div>

                <div className="grid grid-cols-3 lg:grid-cols-3 xl:grid-cols-6 gap-2">
                {drives.map((drive) => {
                    const status = getHighlightStatus(drive.id);
                    
                    // Styles based on status
                    let containerClass = "bg-slate-800/40 border-white/5 hover:bg-slate-800/60"; // Default
                    let ringClass = "";
                    let glowClass = "";
                    let iconClass = status === 'warning' ? 'text-orange-400' : (status === 'safe' ? 'text-emerald-400' : 'text-blue-400');

                    if (status === 'safe') {
                        containerClass = "bg-emerald-900/20 border-emerald-500/50";
                        ringClass = "ring-1 ring-emerald-500/50";
                        glowClass = "shadow-[0_0_30px_-10px_rgba(16,185,129,0.3)]";
                    } else if (status === 'warning') {
                        containerClass = "bg-orange-900/20 border-orange-500/50";
                        ringClass = "ring-1 ring-orange-500/50";
                        glowClass = "shadow-[0_0_30px_-10px_rgba(249,115,22,0.3)]";
                    } else if (status === 'source-safe') {
                        containerClass = "bg-slate-700/50 border-slate-500/50";
                        ringClass = "ring-1 ring-slate-500/50";
                        glowClass = "shadow-[0_0_30px_-10px_rgba(148,163,184,0.3)]";
                        iconClass = "text-slate-300";
                    } else if (status === 'dimmed') {
                        containerClass = "bg-slate-900/20 border-white/5 opacity-40 blur-[1px] scale-95";
                    }

                    return (
                    <div 
                        key={drive.id} 
                        className={`
                            relative p-2.5 rounded-xl border transition-all duration-300 ease-out
                            flex flex-col items-center text-center group
                            ${containerClass} ${ringClass} ${glowClass}
                        `}
                    >
                        {/* Icon */}
                        <div className={`mb-2 p-1.5 rounded-full bg-slate-900/50 shadow-inner ${iconClass}`}>
                            <HardDrive size={18} strokeWidth={1.5} />
                        </div>

                        {/* Info */}
                        <h3 className="text-[10px] font-medium text-slate-200 truncate w-full">{drive.name}</h3>
                        <p className="text-[9px] text-slate-500 mt-0.5 mb-2">{drive.size}</p>

                        {/* Toggle Switch */}
                        <label className="flex items-center gap-1.5 cursor-pointer group/toggle mt-auto">
                            <div className="relative">
                                <input 
                                    type="checkbox" 
                                    className="sr-only peer"
                                    checked={drive.isBackup}
                                    onChange={() => toggleBackup(drive.id)}
                                />
                                <div className="w-6 h-3 bg-slate-700 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-2 after:w-2 after:transition-all peer-checked:bg-emerald-600"></div>
                            </div>
                            <span className={`text-[9px] font-medium transition-colors ${drive.isBackup ? 'text-emerald-400' : 'text-slate-600 group-hover/toggle:text-slate-400'}`}>
                                {drive.isBackup ? 'Backup' : 'Src'}
                            </span>
                        </label>
                    </div>
                    );
                })}
                </div>
            </div>

            {/* Mid Bar: Sort & Search & Toggles */}
            <div className="h-12 border-b border-white/5 bg-slate-800/30 px-6 flex items-center justify-between shrink-0">
                
                {/* Sort Button */}
                <div className="flex items-center gap-2 w-48">
                        <button className="flex items-center gap-2 bg-slate-700/50 hover:bg-slate-700 border border-white/10 text-xs font-medium text-slate-300 px-3 py-1.5 rounded-md shadow-sm transition-colors">
                            <ArrowUpDown size={14} className="text-slate-400" />
                            Sort by Size
                            <ChevronDown size={12} className="text-slate-500 ml-1" />
                        </button>
                </div>

                {/* Center Toggles */}
                <div className="flex items-center gap-1 bg-slate-900/50 p-1 rounded-lg border border-white/5">
                    <button 
                        onClick={() => setShowBackedUp(!showBackedUp)}
                        className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-[11px] font-medium transition-all ${showBackedUp ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 shadow-sm' : 'text-slate-500 hover:text-slate-300'}`}
                    >
                        {showBackedUp ? <CheckCircle2 size={12} /> : <div className="w-3" />}
                        Backed Up
                    </button>
                    <div className="w-px h-4 bg-white/10 mx-1"></div>
                    <button 
                        onClick={() => setShowDuplicates(!showDuplicates)}
                        className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-[11px] font-medium transition-all ${showDuplicates ? 'bg-orange-500/20 text-orange-300 border border-orange-500/30 shadow-sm' : 'text-slate-500 hover:text-slate-300'}`}
                    >
                        {showDuplicates ? <AlertCircle size={12} /> : <div className="w-3" />}
                        Duplicates
                    </button>
                </div>

                {/* Search Input */}
                <div className="relative group w-48 flex justify-end">
                    <Search size={14} className="absolute left-[1.5rem] top-1/2 -translate-y-1/2 text-slate-500 group-focus-within:text-blue-400 transition-colors z-10" />
                    <input 
                        type="text" 
                        placeholder="Search..." 
                        className="bg-slate-900/40 border border-white/10 rounded-md py-1.5 pl-8 pr-3 text-xs text-slate-200 focus:outline-none focus:border-blue-500/40 focus:bg-slate-900/60 focus:ring-1 focus:ring-blue-500/20 w-40 transition-all placeholder-slate-600" 
                    />
                </div>
            </div>

            {/* Bottom Section: File List */}
            <div className="flex-1 bg-slate-900/30 overflow-y-auto scrollbar-thin scrollbar-thumb-slate-700 scrollbar-track-transparent min-h-0">
                <div className="sticky top-0 bg-slate-900/95 backdrop-blur-md border-b border-white/5 px-6 py-2 grid grid-cols-12 text-[10px] font-semibold text-slate-500 uppercase tracking-wider z-10">
                    <div className="col-span-5">Filename</div>
                    <div className="col-span-2 text-right pr-8">Size</div>
                    <div className="col-span-3 text-center">Locations</div>
                    <div className="col-span-2 text-right">Date</div>
                </div>

                <div className="p-2 px-4">
                    {filteredFiles.map((file) => {
                        
                        // Calculate status for pills here to reuse logic
                        const sourceDrivesWithFile = file.drives.filter(dId => {
                            const d = drives.find(drv => drv.id === dId);
                            return d && !d.isBackup;
                        });
                        const backupDrivesWithFile = file.drives.filter(dId => {
                            const d = drives.find(drv => drv.id === dId);
                            return d && d.isBackup;
                        });
                        const isSingleSourceSafe = sourceDrivesWithFile.length === 1 && backupDrivesWithFile.length >= 1;

                        return (
                        <div 
                            key={file.id}
                            onMouseEnter={() => setHoveredFileId(file.id)}
                            onMouseLeave={() => setHoveredFileId(null)}
                            className={`
                                group grid grid-cols-12 items-center py-2.5 px-4 mb-1 rounded-md cursor-default transition-all duration-200
                                ${hoveredFileId === file.id ? 'bg-blue-500/10 border border-blue-500/20 shadow-lg translate-x-0.5' : 'border border-transparent hover:bg-white/5'}
                            `}
                        >
                            {/* Name & Icon */}
                            <div className="col-span-5 flex items-center gap-3 overflow-hidden">
                                <div className="p-1.5 rounded bg-slate-800 text-slate-300 border border-white/5 group-hover:bg-slate-700 group-hover:border-white/10 transition-colors">
                                    {getFileIcon(file.type)}
                                </div>
                                <div className="min-w-0">
                                    <div className={`text-xs font-medium truncate transition-colors ${hoveredFileId === file.id ? 'text-blue-200' : 'text-slate-300'}`}>
                                        {file.name}
                                    </div>
                                    <div className="text-[9px] text-slate-500 truncate opacity-0 group-hover:opacity-100 transition-opacity">
                                        /Volumes/Macintosh HD/Users/Admin/Documents/...
                                    </div>
                                </div>
                            </div>

                            {/* Size */}
                            <div className="col-span-2 text-right pr-8 text-xs text-slate-400 font-mono">
                                {file.size}
                            </div>

                            {/* Locations Pills */}
                            <div className="col-span-3 flex justify-center gap-1">
                                {file.drives.map((driveId) => {
                                    const drive = drives.find(d => d.id === driveId);
                                    const isBackup = drive.isBackup;
                                    
                                    let pillClass = 'bg-slate-700';
                                    if (hoveredFileId === file.id) {
                                        if (isBackup) {
                                            pillClass = 'bg-emerald-500 shadow-[0_0_10px_rgba(16,185,129,0.5)] scale-y-110';
                                        } else if (isSingleSourceSafe) {
                                             pillClass = 'bg-slate-400 shadow-[0_0_10px_rgba(148,163,184,0.5)] scale-y-110';
                                        } else {
                                            pillClass = 'bg-orange-500 shadow-[0_0_10px_rgba(249,115,22,0.5)] scale-y-110';
                                        }
                                    }

                                    return (
                                        <div 
                                            key={driveId}
                                            className={`w-1.5 h-5 rounded-sm transition-all duration-300 ${pillClass}`}
                                            title={drive.name}
                                        />
                                    );
                                })}
                                <span className="ml-2 text-[10px] text-slate-600 font-medium self-center">{file.drives.length}</span>
                            </div>

                            {/* Date */}
                            <div className="col-span-2 text-right text-[10px] text-slate-500">
                                {file.date}
                            </div>
                        </div>
                    )})}
                </div>
            </div>

            {/* Footer */}
            <div className="h-8 bg-slate-900 border-t border-white/5 flex items-center px-4 text-[10px] text-slate-500 justify-between select-none shrink-0">
                <div className="flex gap-4">
                    <span>{drives.length} Drives</span>
                    <span>{filteredFiles.length} Items (of {duplicates.length})</span>
                </div>
                <div className="flex gap-2">
                    <span className="hover:text-slate-300 cursor-pointer">Export</span>
                </div>
            </div>
        </div>
      </div>
    </div>
  );
}