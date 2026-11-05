using System;
using System.IO;
using System.Collections.Generic;
public static class Z9xZipAlign {
    class Entry { public int Cd; public uint Offset; public ushort Method; }
    static ushort U16(byte[] b,int p) { return BitConverter.ToUInt16(b,p); }
    static uint U32(byte[] b,int p) { return BitConverter.ToUInt32(b,p); }
    static void P16(byte[] b,int p,ushort n) { Array.Copy(BitConverter.GetBytes(n),0,b,p,2); }
    static void P32(byte[] b,int p,uint n) { Array.Copy(BitConverter.GetBytes(n),0,b,p,4); }
    static byte[] Read(Stream f,int n) { byte[] b=new byte[n]; int p=0,k; while(p<n) { k=f.Read(b,p,n-p); if(k==0) throw new InvalidDataException("Truncated ZIP"); p+=k; } return b; }
    static void Copy(Stream a,Stream b,long start,long count) { a.Position=start; byte[] buf=new byte[65536]; while(count>0) { int k=a.Read(buf,0,(int)Math.Min(count,buf.Length)); if(k==0) throw new InvalidDataException("Truncated data"); b.Write(buf,0,k); count-=k; } }
    public static void Align(string input,string output) {
      string temp=output+".align-"+Guid.NewGuid().ToString("N");
      try { AlignCore(input,temp); File.Move(temp,output); }
      finally { if(File.Exists(temp)) File.Delete(temp); }
    }
    static void AlignCore(string input,string output) {
      if(!BitConverter.IsLittleEndian) throw new NotSupportedException("Little-endian host required");
      using(FileStream src=File.OpenRead(input)) {
        if(src.Length>UInt32.MaxValue) throw new NotSupportedException("ZIP64 unsupported");
        int tailSize=(int)Math.Min(65557L,src.Length); src.Position=src.Length-tailSize; byte[] tail=Read(src,tailSize); int ep=-1;
        for(int i=tail.Length-22;i>=0;i--) if(U32(tail,i)==0x06054b50 && i+22+U16(tail,i+20)==tail.Length) { ep=i; break; }
        if(ep<0) throw new InvalidDataException("No ZIP EOCD");
        ushort count=U16(tail,ep+10); uint cdSize=U32(tail,ep+12),cdStart=U32(tail,ep+16);
        if(count==65535 || U16(tail,ep+4)!=0 || U16(tail,ep+6)!=0 || U16(tail,ep+8)!=count || cdSize>Int32.MaxValue || (long)cdStart+cdSize!=src.Length-tailSize+ep) throw new NotSupportedException("Split/ZIP64/nonstandard directory unsupported");
        src.Position=cdStart; byte[] cd=Read(src,(int)cdSize); var entries=new List<Entry>(); int cp=0;
        for(int i=0;i<count;i++) {
          if(cp+46>cd.Length || U32(cd,cp)!=0x02014b50 || U16(cd,cp+34)!=0) throw new InvalidDataException("Bad central entry");
          if((U16(cd,cp+8)&1)!=0) throw new NotSupportedException("Encrypted entry unsupported");
          entries.Add(new Entry {Cd=cp,Offset=U32(cd,cp+42),Method=U16(cd,cp+10)});
          cp+=46+U16(cd,cp+28)+U16(cd,cp+30)+U16(cd,cp+32);
        }
        if(cp!=cd.Length || entries.Count==0) throw new InvalidDataException("Unexpected central data");
        entries.Sort(delegate(Entry a,Entry b) {return a.Offset.CompareTo(b.Offset);});
        if(entries[0].Offset!=0) throw new NotSupportedException("ZIP prefix unsupported");
        using(FileStream dst=new FileStream(output,FileMode.CreateNew,FileAccess.Write)) {
          for(int i=0;i<entries.Count;i++) {
            Entry e=entries[i]; long end=i+1<entries.Count ? entries[i+1].Offset : cdStart;
            src.Position=e.Offset; byte[] fixedHeader=Read(src,30);
            if(U32(fixedHeader,0)!=0x04034b50 || U16(fixedHeader,8)!=e.Method) throw new InvalidDataException("Bad local header");
            int name=U16(fixedHeader,26),extra=U16(fixedHeader,28); byte[] names=Read(src,name+extra); long dataStart=src.Position;
            if(end<dataStart || dst.Position>UInt32.MaxValue) throw new InvalidDataException("Bad entry extent");
            P32(cd,e.Cd+42,(uint)dst.Position);
            int pad=e.Method==0 ? (int)((4-((dst.Position+30+names.Length)%4))%4) : 0;
            if(pad>0) {
              if(extra+4+pad>65535) throw new InvalidDataException("Extra field too large");
              P16(fixedHeader,28,(ushort)(extra+4+pad));
            }
            dst.Write(fixedHeader,0,fixedHeader.Length); dst.Write(names,0,names.Length);
            if(pad>0) {byte[] padding=new byte[4+pad]; P16(padding,0,0xd935); P16(padding,2,(ushort)pad); dst.Write(padding,0,padding.Length);}
            Copy(src,dst,dataStart,end-dataStart);
          }
          if(dst.Position>UInt32.MaxValue) throw new NotSupportedException("Output ZIP64 unsupported");
          uint newStart=(uint)dst.Position; dst.Write(cd,0,cd.Length); byte[] eocd=new byte[tail.Length-ep]; Array.Copy(tail,ep,eocd,0,eocd.Length); P32(eocd,16,newStart); dst.Write(eocd,0,eocd.Length);
        }
      }
    }
}
