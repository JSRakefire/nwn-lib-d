/// Terrain (trn, trx)
module nwn.trn.trn;

import std.stdint;
import std.string;
import std.conv: to;
import std.traits;
import std.exception: enforce;
import std.algorithm;
import std.math;
import std.array: array;
import std.typecons: Tuple, tuple;
import nwnlibd.parseutils;
import nwnlibd.geometry;
import gfm.math.vector;
import gfm.math.box;

public import nwn.trn.genericmesh;
public import nwn.twoda;

import std.stdio: stdout, write, writeln, writefln;
version(unittest) import std.exception: assertThrown, assertNotThrown;

///
class TrnParseException : Exception{
	///
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class TrnTypeException : Exception{
	///
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class TrnValueSetException : Exception{
	///
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class TrnInvalidValueException : Exception{
	///
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class ASWMInvalidValueException : TrnInvalidValueException{
	///
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class TRRNInvalidValueException : TrnInvalidValueException{
	///
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class WATRInvalidValueException : TrnInvalidValueException{
	///
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

///Type of a packet's payload
enum TrnPacketType{
	NWN2_TRWH,/// TerrainWidthHeight
	NWN2_TRRN,/// Main terrain data
	NWN2_WATR,/// Water
	NWN2_ASWM,/// Zipped walkmesh data
}
///
template TrnPacketTypeToPayload(TrnPacketType type){
	static if(type == TrnPacketType.NWN2_TRWH)      alias TrnPacketTypeToPayload = TrnNWN2TerrainDimPayload;
	else static if(type == TrnPacketType.NWN2_TRRN) alias TrnPacketTypeToPayload = TrnNWN2MegatilePayload;
	else static if(type == TrnPacketType.NWN2_WATR) alias TrnPacketTypeToPayload = TrnNWN2WaterPayload;
	else static if(type == TrnPacketType.NWN2_ASWM) alias TrnPacketTypeToPayload = TrnNWN2WalkmeshPayload;
	else static assert(0, "Type not supported");
}
///
template TrnPacketPayloadToType(T){
	static if(is(T == TrnNWN2TerrainDimPayload))    alias TrnPacketPayloadToType = TrnPacketType.NWN2_TRWH;
	else static if(is(T == TrnNWN2MegatilePayload)) alias TrnPacketPayloadToType = TrnPacketType.NWN2_TRRN;
	else static if(is(T == TrnNWN2WaterPayload))    alias TrnPacketPayloadToType = TrnPacketType.NWN2_WATR;
	else static if(is(T == TrnNWN2WalkmeshPayload)) alias TrnPacketPayloadToType = TrnPacketType.NWN2_ASWM;
	else static assert(0, "Type not supported");
}
///
TrnPacketType toTrnPacketType(char[4] str, string nwnVersion){
	return (nwnVersion~"_"~str.charArrayToString).to!TrnPacketType;
}
///
char[4] toTrnPacketStr(TrnPacketType type){
	return type.to!(char[])[5 .. 9];
}


///
struct TrnPacket{

	/// Create an packet with default values
	this(TrnPacketType type){
		m_type = type;

		typeswitch:
		final switch(m_type){
			static foreach(T ; EnumMembers!TrnPacketType){
				case T:
					alias PT = TrnPacketTypeToPayload!T;
					structData = new PT();
					break typeswitch;
			}
		}
	}

	///
	this(TrnPacketType type, in ubyte[] payloadData){
		import std.traits: EnumMembers;

		m_type = type;

		typeswitch:
		final switch(type) with(TrnPacketType){
			static foreach(TYPE ; EnumMembers!TrnPacketType){
				case TYPE:
					alias PAYLOAD = TrnPacketTypeToPayload!TYPE;
					structData = new PAYLOAD(payloadData);
					break typeswitch;
			}
		}
	}

	///
	this(T)(in T packet)
	if(is(T: TrnNWN2TerrainDimPayload) || is(T: TrnNWN2MegatilePayload) || is(T: TrnNWN2WaterPayload) || is(T: TrnNWN2WalkmeshPayload)){
		this(TrnPacketPayloadToType!T, packet.serialize());
	}

	@property{
		///
		TrnPacketType type()const{return m_type;}
	}
	private TrnPacketType m_type;

	/// as!TrnNWN2WalkmeshPayload
	ref inout(T) as(T)() inout if(is(typeof(TrnPacketPayloadToType!T) == TrnPacketType)) {
		assert(type == TrnPacketPayloadToType!T, "Type mismatch");
		return *cast(inout(T)*)structData;
	}

	/// as!(TrnPacketType.NWN2_ASWM)
	ref inout(TrnPacketTypeToPayload!T) as(TrnPacketType T)() inout{
		return as!(TrnPacketTypeToPayload!T);
	}

	/// Serialize a single TRN packet
	ubyte[] serialize() const {
		final switch(type) with(TrnPacketType){
			static foreach(TYPE ; EnumMembers!TrnPacketType){
				case TYPE:
					return as!TYPE.serialize();
			}
		}
	}

private:
	void* structData;
}






/// TRN / TRX file parsing
class Trn{
	/// Empty TRN file
	this(){}

	/// Parse a TRN file
	this(in string path){
		import std.file: read;
		this(cast(ubyte[])path.read());
	}

	/// Parse TRN raw data
	this(in ubyte[] rawData){
		enforce!TrnParseException(rawData.length>Header.sizeof, "Data is too small to contain the header");

		auto header =        cast(Header*)        rawData.ptr;
		auto packetIndices = cast(PacketIndices*)(rawData.ptr+Header.sizeof);

		m_nwnVersion = header.file_type.charArrayToString;
		m_versionMajor = header.version_major;
		m_versionMinor = header.version_minor;

		foreach(i ; 0..header.resource_count){
			immutable type = packetIndices[i].type.toTrnPacketType(nwnVersion);
			immutable offset = packetIndices[i].offset;

			immutable packet = cast(immutable Packet*)(rawData.ptr+offset);
			immutable packetType = packet.type.toTrnPacketType(nwnVersion);
			immutable packetLength = packet.payload_length;

			enforce!TrnParseException(type==packetType, "Packet type does not match the one referenced in packet indices");

			packets ~= TrnPacket(type, (&packet.payload_start)[0..packetLength]);

			version(unittest){
				auto ser = packets[$ - 1].serialize();
				assert(ser == (&packet.payload_start)[0..packetLength], format!"Mismatch on packet %d (%s)"(i, packetType));
			}
		}

		version(unittest){
			assert(serialize() == rawData);
		}
	}

	///
	ubyte[] serialize() const {

		auto header = Header(
			m_nwnVersion.dup[0..4],
			m_versionMajor.to!uint16_t,
			m_versionMinor.to!uint16_t,
			packets.length.to!uint32_t);

		PacketIndices[] indices;
		indices.length = packets.length;

		uint32_t offset = (header.sizeof + PacketIndices.sizeof * indices.length).to!uint32_t;
		ubyte[] packetsData;
		foreach(i, ref packet ; packets){
			auto typeStr = packet.type.toTrnPacketStr();

			indices[i].type = typeStr;
			indices[i].offset = offset;
			auto packetData = packet.serialize();

			ChunkWriter cw;
			cw.put(typeStr, packetData.length.to!uint32_t, packetData);
			packetsData ~= cw.data;
			offset += cw.data.length;
		}


		ChunkWriter cw;
		cw.put(
			header,
			indices,
			packetsData);
		return cw.data;
	}


	///
	@property string nwnVersion()const{return m_nwnVersion;}
	///
	package string m_nwnVersion;

	///
	@property uint versionMajor()const{return m_versionMajor;}
	///
	package uint m_versionMajor;

	///
	@property uint versionMinor()const{return m_versionMinor;}
	///
	package uint m_versionMinor;

	/// TRN packet list
	TrnPacket[] packets;

	/// foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){}
	int opApply(T)(scope int delegate(ref T packet) dlg)
	if(is(typeof(TrnPacketPayloadToType!T) == TrnPacketType)) {
		int res = 0;
		foreach(ref packet ; packets){
			if(packet.type == TrnPacketPayloadToType!T){
				if((res = dlg(packet.as!T)) != 0)
					return res;
			}
		}
		return res;
	}


private:
	static align(1) struct Header{
		static assert(this.sizeof == 12);
		char[4] file_type;
		uint16_t version_major;
		uint16_t version_minor;
		uint32_t resource_count;
	}
	static align(1) struct PacketIndices{
		static assert(this.sizeof == 8);
		char[4] type;
		uint32_t offset;
	}
	static align(1) struct Packet{
		static assert(this.sizeof == 8+1);
		char[4] type;
		uint32_t payload_length;
		ubyte payload_start;
	}
}



/// Terrain dimensions (TRWH)
struct TrnNWN2TerrainDimPayload{
	uint32_t width;/// Width in megatiles
	uint32_t height;/// Height in megatiles
	uint32_t id;/// Unknown

	/// Build packet with raw data
	this(in ubyte[] payload){
		width = *(cast(uint32_t*)&payload[0]);
		height = *(cast(uint32_t*)&payload[4]);
		id = *(cast(uint32_t*)&payload[8]);
	}

	///
	ubyte[] serialize() const {
		ChunkWriter cw;
		cw.put(width, height, id);
		return cw.data;
	}
}

/// Megatile information (TRRN)
struct TrnNWN2MegatilePayload{
	char[128] name;///name of the terrain
	///
	static align(1) struct Texture{
		static assert(this.sizeof == 44);
		char[32] name;
		float[3] color;/// rgb
	}
	Texture[6] textures;/// Textures on the megatile, with their blend color
	///
	static align(1) struct Vertex{
		static assert(this.sizeof == 44);
		float[3] position;/// x y z
		float[3] normal;  /// normal vector
		ubyte[4] tinting; /// BGRA format. A is unused.
		float[2] uv;/// Texture coordinates
		float[2] weights; /// XY1
	}
	Vertex[] vertices;/// Terrain geometry
	///
	static align(1) struct Triangle{
		uint16_t[3] vertices;///Triangle vertex indices in $(D TrnNWN2TerrainDimPayload.vertices)
	}
	/// Walkmesh grid triangles positions.
	/// Each uint16_t an index in `vertices` corresponding to a triangle vertex
	Triangle[] triangles;
	ubyte[] dds_a;/// 32 bit DDS bitmap. r,g,b,a defines the intensity of textures 0,1,2,3
	ubyte[] dds_b;/// 32 bit DDS bitmap. r,g defines the intensity of textures 4,5
	///
	static struct Grass{
		char[32] name;///
		char[32] texture;///
		///
		static align(1) struct Blade{
			static assert(this.sizeof == 36);
			float[3] position;///
			float[3] direction;///
			float[3] dimension;///
		}
		Blade[] blades;///
	}
	Grass[] grass;/// Grass "objects"

	/// Build packet with raw data
	this(in ubyte[] payload){
		auto data = ChunkReader(payload);

		name = data.read!(char[128]);
		//TODO: there is other data than name in this array

		foreach(ref texture ; textures){
			texture.name = data.read!(char[32]);
		}
		foreach(ref texture ; textures){
			texture.color = data.read!(float[3]);
		}
		immutable vertices_length  = data.read!uint32_t;
		immutable triangles_length = data.read!uint32_t;
		vertices = data.readArray!Vertex(vertices_length).dup;
		triangles = data.readArray!Triangle(triangles_length).dup;

		immutable dds_a_length = data.read!uint32_t;
		dds_a = data.readArray(dds_a_length).dup;
		immutable dds_b_length = data.read!uint32_t;
		dds_b = data.readArray(dds_b_length).dup;

		immutable grass_count = data.read!uint32_t;
		grass.length = grass_count;
		foreach(ref g ; grass){
			g.name = data.read!(typeof(g.name)).dup;
			g.texture = data.read!(typeof(g.texture));
			immutable blades_count = data.read!uint32_t;
			g.blades.length = blades_count;
			foreach(ref blade ; g.blades){
				blade = data.readPackedStruct!(Grass.Blade);
			}
		}

		enforce!TrnParseException(data.read_ptr == payload.length,
			(payload.length - data.read_ptr).to!string ~ " bytes were not read at the end of TRRN");
	}

	///
	ubyte[] serialize() const {
		ChunkWriter cw;
		cw.put(name);
		foreach(ref texture ; textures)
			cw.put(texture.name);
		foreach(ref texture ; textures)
			cw.put(texture.color);

		cw.put(
			vertices.length.to!uint32_t,
			triangles.length.to!uint32_t,
			vertices,
			triangles,
			dds_a.length.to!uint32_t, dds_a,
			dds_b.length.to!uint32_t, dds_b,
			grass.length.to!uint32_t);

		foreach(ref g ; grass){
			cw.put(
				g.name,
				g.texture,
				g.blades.length.to!uint32_t, g.blades);
		}

		return cw.data;
	}

	/// Export terrain mesh to a `GenericMesh` struct
	GenericMesh toGenericMesh() const {
		GenericMesh ret;

		ret.vertices.length = vertices.length;
		foreach(i, ref v ; vertices)
			ret.vertices[i] = vec3f(v.position);

		ret.triangles.length = triangles.length;
		foreach(i, ref t ; triangles)
			ret.triangles[i] = GenericMesh.Triangle(t.vertices.to!(uint32_t[3]));

		return ret;
	}

	/// Check if the TRRN contains valid data
	void validate() const {
		import nwn.dds;

		try new Dds(dds_a);
		catch(Exception e)
			throw new TRRNInvalidValueException("dds_a is invalid or format is not supported", __FILE__, __LINE__, e);
		try new Dds(dds_b);
		catch(Exception e)
			throw new TRRNInvalidValueException("dds_b is invalid or format is not supported", __FILE__, __LINE__, e);

		foreach(vi, v ; vertices){
			enforce!TRRNInvalidValueException(v.position[].all!"!a.isNaN",
				format!"vertices[%d] has an invalid position: %s"(vi, v));
		}

		immutable vtxLen = vertices.length;
		foreach(ti, ref t ; triangles){
			foreach(vi, v ; t.vertices)
				enforce!TRRNInvalidValueException(v < vtxLen,
					format!"triangles[%d].vertices[%d] = %d is out of bounds [0;%d["(ti, vi, v, vtxLen));
		}
	}
}

/// Water information (WATR)
struct TrnNWN2WaterPayload{
	/// WATR name.
	///
	/// NWN2 seems to set it to `""` and fill the remaining bytes with garbage.
	char[32] name;
	ubyte[96] unknown;///
	float[3] color;/// R,G,B
	float[2] ripple;/// Ripples
	float smoothness;/// Smoothness
	float reflect_bias;/// Reflection bias
	float reflect_power;/// Reflection power
	float specular_power;/// Specular map power
	float specular_cofficient;/// Specular map coefficient
	///
	static align(1) struct Texture{
		static assert(this.sizeof == 48);
		char[32] name;/// Texture name
		float[2] direction;/// Scrolling direction
		float rate;/// Scrolling speed
		float angle;/// Scrolling angle in radiant
	}
	Texture[3] textures;/// Water textures
	float[2] uv_offset;/// x,y offset in water-space <=> megatile_coordinates/8
	///
	static align(1) struct Vertex{
		static assert(this.sizeof == 28);
		float[3] position;/// x y z
		float[2] uvx5;/// XY5 (set to XY1 * 5.0)
		float[2] uv;/// XY1
	}
	///
	Vertex[] vertices;
	///
	static align(1) struct Triangle{
		static assert(this.sizeof == 6);
		uint16_t[3] vertices;///Triangle vertex indices in $(D TrnNWN2WaterPayload.vertices)
	}
	/// Walkmesh grid triangles positions.
	/// Each uint16_t an index in `vertices` corresponding to a triangle vertex
	Triangle[] triangles;
	uint32_t[] triangles_flags;/// 0 = has water, 1 = no water
	ubyte[] dds;/// DDS bitmap
	uint32_t[2] megatile_position;/// Position of the associated megatile in the terrain


	/// Build packet with raw data
	this(in ubyte[] payload){
		auto data = ChunkReader(payload);

		name                = data.read!(typeof(name));
		unknown             = data.read!(typeof(unknown));
		color               = data.read!(typeof(color));
		ripple              = data.read!(typeof(ripple));
		smoothness          = data.read!(typeof(smoothness));
		reflect_bias        = data.read!(typeof(reflect_bias));
		reflect_power       = data.read!(typeof(reflect_power));
		specular_power      = data.read!(typeof(specular_power));
		specular_cofficient = data.read!(typeof(specular_cofficient));
		textures            = data.read!(typeof(textures));
		uv_offset           = data.read!(typeof(uv_offset));

		immutable vertices_length  = data.read!uint32_t;
		immutable triangles_length = data.read!uint32_t;
		assert(data.read_ptr == 328);

		vertices = data.readArray!Vertex(vertices_length).dup;
		triangles = data.readArray!Triangle(triangles_length).dup;
		triangles_flags = data.readArray!uint32_t(triangles_length).dup;

		immutable dds_length = data.read!uint32_t;
		dds = data.readArray(dds_length).dup;

		megatile_position = data.read!(typeof(megatile_position));

		enforce!TrnParseException(data.read_ptr == payload.length,
			(payload.length - data.read_ptr).to!string ~ " bytes were not read at the end of WATR");

		validate();
	}

	///
	ubyte[] serialize() const {
		ChunkWriter cw;
		cw.put(
			name,
			unknown,
			color,
		);
		// arguments are separated because of https://issues.dlang.org/show_bug.cgi?id=21301
		cw.put(
			ripple,
			smoothness,
			reflect_bias,
			reflect_power,
			specular_power,
			specular_cofficient,
			textures,
			uv_offset,
			vertices.length.to!uint32_t,
			triangles.length.to!uint32_t,
			vertices,
			triangles,
			triangles_flags,
			dds.length.to!uint32_t, dds,
			megatile_position,
		);
		return cw.data;
	}

	///
	void validate(bool strict = false) const {
		import nwn.dds;

		// TODO: can't parse this kind of DDS atm
		//try new Dds(dds);
		//catch(Exception e)
		//	throw new WATRInvalidValueException("dds is invalid or format is not supported", __FILE__, __LINE__, e);

		enforce!WATRInvalidValueException(triangles.length == triangles_flags.length,
			format!"triangles.length (=%d) must match triangles_flags.length (=%d)"(triangles.length, triangles_flags.length));

		foreach(vi, v ; vertices){
			enforce!WATRInvalidValueException(v.position[].all!"!a.isNaN",
				format!"vertices[%d] has an invalid position: %s"(vi, v));
		}

		immutable vtxLen = vertices.length;
		foreach(ti, ref t ; triangles){
			foreach(vi, v ; t.vertices)
				enforce!WATRInvalidValueException(v < vtxLen,
					format!"triangles[%d].vertices[%d] = %d is out of bounds [0;%d["(ti, vi, v, vtxLen));
		}

		if(strict){
			foreach(i, f ; triangles_flags){
				enforce!WATRInvalidValueException(f == 0 || f == 1,
					format!"triangles_flags[%d]: Unknown flag value: %b"(i, f));
			}
		}
	}


	string dump() const {
		string ret;
		ret ~= format!"name: %s\n"(name);
		ret ~= format!"unknown: %(%02x %)\n"(unknown);
		ret ~= format!"color: %s\n"(color);
		ret ~= format!"ripple: %s\n"(ripple);
		ret ~= format!"smoothness: %s\n"(smoothness);
		ret ~= format!"reflect_bias: %s\n"(reflect_bias);
		ret ~= format!"reflect_power: %s\n"(reflect_power);
		ret ~= format!"specular_power: %s\n"(specular_power);
		ret ~= format!"specular_cofficient: %s\n"(specular_cofficient);

		foreach(i, tex ; textures){
			ret ~= format!"texture.%d:\n"(i);
			ret ~= format!"    name: %s:\n"(tex.name);
			ret ~= format!"    direction: %s:\n"(tex.direction);
			ret ~= format!"    rate: %s:\n"(tex.rate);
			ret ~= format!"    angle: %s:\n"(tex.angle);
		}

		ret ~= format!"uv_offset: %s\n"(uv_offset);

		ret ~= "vertices:\n";
		foreach(i, vtx ; vertices)
			ret ~= format!"    %d: %s\n"(i, vtx);

		ret ~= "triangles:\n";
		foreach(i, tri ; triangles)
			ret ~= format!"    %d: %s\n"(i, tri);

		ret ~= "triangles_flags:\n";
		foreach(i, tf ; triangles_flags)
			ret ~= format!"    %d: %s\n"(i, tf);

		ret ~= "dds:\n";
		ret ~= dds.dumpByteArray;

		ret ~= format!"megatile_position: %s\n"(megatile_position);

		return ret;
	}
}

/// Compressed walkmesh (only contained inside TRX files) (ASWM)
struct TrnNWN2WalkmeshPayload{

	/// ASWM packet header
	static align(1) struct Header{
		static assert(this.sizeof == 53);
		align(1):
		/// ASWM version. NWN2Toolset generates version 0x6c, but some NWN2 official campaign files are between 0x69 and 0x6c.
		uint32_t aswm_version;
		/// ASWM name (probably useless)
		char[32] name;
		/// Always true
		bool owns_data;
		private uint32_t vertices_count;
		private uint32_t edges_count;
		private uint32_t triangles_count;
		uint32_t unknownB;
	}
	/// ditto
	Header header;

	static align(1) union Vertex {
		static assert(this.sizeof == 12);
		align(1):

		float[3] position;

		private static struct Xyz{ float x, y, z; }
		Xyz _xyz;
		alias _xyz this;
	}
	Vertex[] vertices;

	/// Edge between two triangles
	static align(1) struct Edge{
		static assert(this.sizeof == 16);
		align(1):
		uint32_t[2] vertices; /// Vertex indices drawing the edge line
		uint32_t[2] triangles; /// Joined triangles (`uint32_t.max` if none)
	}
	/// For v69 only
	private static align(1) struct Edge_v69 {
		static assert(this.sizeof == 52);
		align(1):
		uint32_t[2] vertices; /// Vertex indices drawing the edge line
		uint32_t[2] triangles; /// Joined triangles (`uint32_t.max` if none)
		uint32_t[9] _reserved;
		Edge upgrade() const{
			return Edge(vertices, triangles);
		}
	}
	Edge[] edges;

	/// Mesh Triangle + pre-calculated data + metadata
	static align(1) struct Triangle{
		static assert(this.sizeof == 64);
		align(1):
		uint32_t[3] vertices; /// Vertex indices composing the triangle
		/// Edges to other triangles (`uint32_t.max` if none, but there should always be 3)
		///
		/// Every `linked_edges` should have its associated `linked_triangles` at the same index
		uint32_t[3] linked_edges;
		/// Adjacent triangles (`uint32_t.max` if none)
		///
		/// Every `linked_triangles` should have its associated `linked_edges` at the same index
		uint32_t[3] linked_triangles;
		float[2] center; /// X / Y coordinates of the center of the triangle. Calculated by avg the 3 vertices coordinates.
		float[3] normal; /// Normal vector
		float dot_product; /// Dot product at plane
		uint16_t island; /// Index in the `TrnNWN2WalkmeshPayload.islands` array.
		uint16_t flags; /// See `Flags`

		enum Flags {
			walkable  = 0x01, /// if the triangle can be walked on. Note the triangle needs path tables to be really walkable
			clockwise = 0x04, /// vertices are wound clockwise and not ccw
			dirt      = 0x08, /// Floor type (for sound effects)
			grass     = 0x10, /// ditto
			stone     = 0x20, /// ditto
			wood      = 0x40, /// ditto
			carpet    = 0x80, /// ditto
			metal     = 0x100, /// ditto
			swamp     = 0x200, /// ditto
			mud       = 0x400, /// ditto
			leaves    = 0x800, /// ditto
			water     = 0x1000, /// ditto
			puddles   = 0x2000, /// ditto

			soundstepFlags = dirt | grass | stone | wood | carpet | metal | swamp | mud | leaves | water | puddles,
		}
	}
	/// For v6a only
	private static align(1) struct Triangle_v6a{
		static assert(this.sizeof == 68);
		align(1):
		uint32_t  _reserved;
		uint32_t[3] vertices;
		uint32_t[3] linked_edges;
		uint32_t[3] linked_triangles;
		float[2] center;
		float[3] normal;
		float dot_product;
		uint16_t island;
		uint16_t flags;
		Triangle upgrade() const{
			return Triangle(vertices, linked_edges, linked_triangles, center, normal, dot_product, island, flags);
		}
	}
	/// For v69 only
	private static align(1) struct Triangle_v69{
		static assert(this.sizeof == 88);
		align(1):
		uint32_t  _reserved0;
		uint32_t flags;
		uint32_t[3] vertices;
		uint32_t[3] linked_edges;
		uint32_t[3] linked_triangles;
		uint32_t[3]  _reserved1;
		float[2] center;
		uint32_t  _reserved2;
		float[3] normal;
		float dot_product;
		uint16_t  _reserved3;
		uint16_t island;
		Triangle upgrade() const{
			return Triangle(vertices, linked_edges, linked_triangles, center, normal, dot_product, island, cast(uint16_t)flags);
		}
	}
	Triangle[] triangles;

	/// Always 31 in TRX files, 15 in TRN files
	uint32_t tiles_flags;
	/// Width in meters of a terrain tile (most likely to be 10.0)
	float tiles_width;
	/// Number of tiles along Y axis
	/// TODO: double check height = Y
	uint32_t tiles_grid_height;
	/// Number of tiles along X axis
	/// TODO: double check width = X
	uint32_t tiles_grid_width;
	/// Width of the map borders in tiles (8 means that 8 tiles will be removed on each side)
	uint32_t tiles_border_size;

	/// Tile with its path table
	static struct Tile {

		static align(1) struct Header {
			static assert(this.sizeof == 57);
			align(1):
			char[32] name; /// Last time I checked it was complete garbage
			ubyte owns_data;/// 1 if the tile stores vertices / edges. Usually 0
			uint32_t vertices_count; /// Number of vertices in this tile
			uint32_t edges_count; /// Number of edges in this tile
			uint32_t triangles_count; /// Number of triangles in this tile (walkable + unwalkable)
			float size_x;/// Always 0 ?
			float size_y;/// Always 0 ?

			/// This value will be added to each triangle index in the PathTable
			uint32_t triangles_offset;
		}
		Header header;

		/// Only used if `header.owns_data == true`
		Vertex[] vertices;

		/// Only used if `header.owns_data == true`
		Edge[] edges;

		/**
		Tile pathing information

		Notes:
		- "local" refers to the local triangle index. The aswm triangle index
		  can be retrieved by adding Tile.triangles_offset
		- Each triangle referenced here is only referenced once across all the
		  tiles of the ASWM
		*/
		static struct PathTable {

			static align(1) struct Header {
				static assert(this.sizeof == 13);
				align(1):

				enum Flags {
					rle       = 0x01,
					zcompress = 0x02,
				}
				uint32_t flags; /// Always 0. Used to set path table compression
				private uint32_t _local_to_node_length; /// use `local_to_node.length` instead
				private ubyte _node_to_local_length; /// use `node_to_local.length` instead
				uint32_t rle_table_size; /// Always 0 ? probably related to Run-Length Encoding
			}
			/// For v69 to v6b
			private static align(1) struct Header_v69 {
				static assert(this.sizeof == 10);
				align(1):
				uint32_t flags;
				ubyte _local_to_node_length;
				ubyte _node_to_local_length;
				uint32_t rle_table_size;
				Header upgrade() const{
					return Header(flags, _local_to_node_length, _node_to_local_length, rle_table_size);
				}
			}
			Header header;

			/**
			List of node indices for each triangle in the tile

			`local_to_node[triangle_local_index]` represents an index value to
			be used with nodes (see `nodes` for how to use it)

			All triangles (even non walkable) must be represented here.
			Triangle indices that are not used in this tile must have a `0xFF`
			value.
			*/
			ubyte[] local_to_node;

			/**
			Node index to local triangle index

			Values must not be uint32_t.max
			*/
			uint32_t[] node_to_local;

			/**
			Node list

			This is used to determine which triangle a creature should go next
			to reach a destination triangle.

			`nodes[header.node_to_local_length * FromLTNIndex + DestLTNIndex]
			& 0b0111_1111` is an index in `node_to_local` array, containing
			the next triangle to go to in order to reach destination.

			`FromLTNIndex`, `DestLTNIndex` are values found inside the
			`local_to_node` array.
			<ul>
			$(LI `value & 0b0111_1111` is an index in `node_to_local` table)
			$(LI `value & 0b1000_0000` is > 0 if there is a clear line of
			sight between the two triangle. It's not clear what LOS is since
			two linked triangles on flat ground may not have LOS = 1 in game
			files.)
			</ul>

			If FromLTNIndex == DestLTNIndex, the value must be set to 255.

			Note: does not contain any 127 = 0b0111_1111 values
			*/
			ubyte[] nodes;

			/// Always 0b0001_1111 = 31 ?
			uint32_t flags;
		}
		PathTable path_table;

		private void parse(ref ChunkReader wmdata, uint32_t aswmVersion=0x6c){
			header = wmdata.read!Header;

			if(header.owns_data){
				vertices = wmdata.readArray!Vertex(header.vertices_count).dup;
				switch(aswmVersion){
					case 0x69:
						edges = wmdata.readArray!Edge_v69(header.edges_count).map!(a => a.upgrade()).array;
						break;
					case 0x6a: .. case 0x6c:
						edges = wmdata.readArray!Edge(header.edges_count).dup;
						break;
					default: enforce(0, "Unsupported ASWM version " ~ aswmVersion.format!"0x%02x");
				}
			}

			with(path_table){
				switch(aswmVersion){
					case 0x69: .. case 0x6b:
						header = wmdata.read!Header_v69.upgrade();
						break;
					case 0x6c:
						header = wmdata.read!Header;
						break;
					default: enforce(0, "Unsupported ASWM version " ~ aswmVersion.format!"0x%02x");
				}

				enforce!TrnParseException((header.flags & (Header.Flags.rle | Header.Flags.zcompress)) == 0, "Compressed path tables not supported");

				local_to_node = wmdata.readArray!ubyte(header._local_to_node_length).dup;
				switch(aswmVersion){
					case 0x69, 0x6a:
						// No node_to_local data
						break;
					case 0x6b:
						node_to_local = wmdata.readArray!uint8_t(header._node_to_local_length).map!(a => cast(uint32_t)a).array;
						break;
					case 0x6c:
						node_to_local = wmdata.readArray!uint32_t(header._node_to_local_length).dup;
						break;
					default: enforce(0, "Unsupported ASWM version " ~ aswmVersion.format!"0x%02x");
				}
				nodes = wmdata.readArray!ubyte(header._node_to_local_length ^^ 2).dup;

				flags = wmdata.read!(typeof(flags));
			}
		}
		private void serialize(ref ChunkWriter uncompData) const {

			uncompData.put(
				header,
				vertices,
				edges);

			immutable tcount = header.triangles_count;

			with(path_table){
				// Update header
				PathTable.Header updatedHeader = header;
				updatedHeader._local_to_node_length = local_to_node.length.to!uint32_t;
				updatedHeader._node_to_local_length = node_to_local.length.to!ubyte;

				assert(nodes.length == node_to_local.length ^^ 2, "Bad number of path table nodes");
				assert(local_to_node.length == tcount, "local_to_node length should match header.triangles_count");

				// serialize
				uncompData.put(
					updatedHeader,
					local_to_node,
					node_to_local,
					nodes,
					flags);
			}
		}

		string dump() const {
			import std.range: chunks;
			return format!"TILE header: name: %(%s, %)\n"([header.name])
			     ~ format!"        owns_data: %s, vert_cnt: %s, edge_cnt: %s, tri_cnt: %s\n"(header.owns_data, header.vertices_count, header.edges_count, header.triangles_count)
			     ~ format!"        size_x: %s, size_y: %s\n"(header.size_x, header.size_y)
			     ~ format!"        triangles_offset: %s\n"(header.triangles_offset)
			     ~ format!"     vertices: %s\n"(vertices)
			     ~ format!"     edges: %s\n"(edges)
			     ~        "     path_table: \n"
			     ~ format!"       header: flags: %s, ltn_len: %d, ntl_len: %s, rle_len: %s\n"(path_table.header.flags, path_table.header._local_to_node_length, path_table.header._node_to_local_length, path_table.header.rle_table_size)
			     ~ format!"       ltn:   %(%3d %)\n"(path_table.local_to_node)
			     ~ format!"       ntl:   %(%3d %)\n"(path_table.node_to_local)
			     ~ format!"       nodes: %(%-(%s%)\n              %)\n"(
			     	path_table.node_to_local.length == 0 ?
			     	[] : path_table.nodes.map!(a => (((a & 128)? "*" : " ") ~ (a & 127).to!string).rightJustify(4)).chunks(path_table.node_to_local.length).array)
			     ~ format!"       flags: %s\n"(path_table.flags);
		}

		ubyte getPathNode(uint32_t fromGTriIndex, uint32_t toGTriIndex) const {
			assert(header.triangles_offset <= fromGTriIndex && fromGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"From triangle index "~fromGTriIndex.to!string~" is not in tile path table");
			assert(header.triangles_offset <= toGTriIndex && toGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"To triangle index "~toGTriIndex.to!string~" is not in tile path table");


			immutable nodeFrom = path_table.local_to_node[fromGTriIndex - header.triangles_offset];
			immutable nodeTo = path_table.local_to_node[toGTriIndex - header.triangles_offset];

			if(nodeFrom == 0xff || nodeTo == 0xff)
				return 0xff;

			return path_table.nodes[nodeFrom * path_table.node_to_local.length + nodeTo];
		}

		/**
		Calculate the fastest route between two triangles of a tile. The tile need to be baked, as it uses existing path tables.
		*/
		uint32_t[] findPath(in uint32_t fromGTriIndex, in uint32_t toGTriIndex) const {
			assert(header.triangles_offset <= fromGTriIndex && fromGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"From triangle index "~fromGTriIndex.to!string~" is not in tile path table");
			assert(header.triangles_offset <= toGTriIndex && toGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"To triangle index "~toGTriIndex.to!string~" is not in tile path table");

			uint32_t from = fromGTriIndex;

			int iSec = 0;
			uint32_t[] ret;
			while(from != toGTriIndex && iSec++ < 1000){
				auto node = getPathNode(from, toGTriIndex);
				if(node == 0xff)
					return ret;

				from = path_table.node_to_local[node & 0b0111_1111] + header.triangles_offset;
				ret ~= from;

			}
			assert(iSec < 1000, "Tile precalculated paths lead to a loop (from="~fromGTriIndex.to!string~", to="~toGTriIndex.to!string~")");
			return ret;
		}

		/// Check a single tile. You should use `TrnNWN2WalkmeshPayload.validate()` instead
		void validate(in TrnNWN2WalkmeshPayload aswm, uint32_t tileIndex, bool strict = false) const {
			import std.typecons: Tuple;
			alias Ret = Tuple!(bool,"valid", string,"error");
			immutable nodesLen = path_table.nodes.length;
			immutable ntlLen = path_table.node_to_local.length;
			immutable ltnLen = path_table.local_to_node.length;
			immutable offset = header.triangles_offset;

			enforce!ASWMInvalidValueException(ltnLen == 0 || header.triangles_count == ltnLen,
				"local_to_node: length ("~ltnLen.to!string~") does not match triangles_count ("~header.triangles_count.to!string~")");

			enforce!ASWMInvalidValueException(offset < aswm.triangles.length || (offset == aswm.triangles.length && ltnLen == 0),
				"header.triangles_offset: offset ("~offset.to!string~") points to invalid triangles");

			enforce!ASWMInvalidValueException(offset + ltnLen <= aswm.triangles.length,
				"local_to_node: contains data for invalid triangles");


			if(strict){
				immutable edgeCnt = aswm.triangles[offset .. offset + header.triangles_count]
					.map!((ref a) => a.linked_edges[])
					.join
					.filter!(a => a != a.max)
					.array.dup
					.sort
					.uniq
					.array.length.to!uint32_t;
				immutable vertCnt = aswm.triangles[offset .. offset + header.triangles_count]
					.map!((ref a) => a.vertices[])
					.join
					.filter!(a => a != a.max)
					.array.dup
					.sort
					.uniq
					.array.length.to!uint32_t;

				enforce!ASWMInvalidValueException(edgeCnt == header.edges_count,
					"header.edges_count: Wrong number of edges: got "~header.edges_count.to!string~", counted "~edgeCnt.to!string);
				enforce!ASWMInvalidValueException(vertCnt == header.vertices_count,
					"header.vertices_count: Wrong number of vertices: got "~header.vertices_count.to!string~", counted "~vertCnt.to!string);
			}

			if(strict){
				uint32_t tileX = tileIndex % aswm.tiles_grid_width;
				uint32_t tileY = tileIndex / aswm.tiles_grid_width;
				auto tileAABB = box2f(
					vec2f(tileX * aswm.tiles_width,       tileY * aswm.tiles_width),
					vec2f((tileX + 1) * aswm.tiles_width, (tileY + 1) * aswm.tiles_width));

				foreach(i ; offset .. offset + header.triangles_count){
					enforce!ASWMInvalidValueException(tileAABB.contains(vec2f(aswm.triangles[i].center)),
						"Triangle "~i.to!string~" is outside of the tile AABB");
				}
			}

			// Path table
			if(aswm.header.aswm_version >= 0x6b){
				enforce!ASWMInvalidValueException(nodesLen == ntlLen ^^ 2,
					format!"Wrong number of nodes (%d instead of %d)"(nodesLen, ntlLen ^^ 2));
			}
			else{
				enforce!ASWMInvalidValueException(ntlLen == 0,
					"Wrong number of nodes (shoule be 0)");
			}

			if(nodesLen < 0x7f){
				foreach(j, node ; path_table.nodes){
					enforce!ASWMInvalidValueException(node == 0xff || (node & 0b0111_1111) < ntlLen,
						"nodes["~j.to!string~"]: Illegal value "~node.to!string ~ " (should be either 255 or less than 127)");
				}
			}
			if(nodesLen < 0xff){
				foreach(j, node ; path_table.local_to_node){
					enforce!ASWMInvalidValueException(node == 0xff || node < nodesLen,
						"local_to_node["~j.to!string~"]: Illegal value"~node.to!string ~ " (should be either 255 or an existing node index)");
				}
			}

			foreach(j, ntl ; path_table.node_to_local){
				enforce!ASWMInvalidValueException(ntl + offset < aswm.triangles.length,
					"node_to_local["~j.to!string~"]: triangle index "~ntl.to!string~" out of bounds");
			}
		}
	}
	/// Map tile list
	/// Non border tiles have `header.vertices_count > 0 || header.edges_count > 0 || header.triangles_count > 0`
	Tile[] tiles;

	/**
	Tile or fraction of a tile used for pathfinding through large distances.

	<ul>
	<li>The island boundaries match exactly the tile boundaries</li>
	<li>Generally you have one island per tile.</li>
	<li>You can have multiple islands for one tile, like if one side of the tile is not accessible from the other side</li>
	</ul>
	*/
	static struct Island {
		static align(1) struct Header {
			static assert(this.sizeof == 24);
			align(1):
			uint32_t index; /// Index of the island in the aswm.islands array. TODO: weird
			uint32_t tile; /// Value looks pretty random, but is identical for all islands
			Vertex center; /// Center of the island. Z is always 0. TODO: find how it is calculated
			uint32_t triangles_count; /// Number of triangles in this island
		}
		Header header;
		uint32_t[] adjacent_islands; /// Adjacent islands
		float[] adjacent_islands_dist; /// Distances between adjacent islands (probably measured between header.center)

		/**
		List of triangles that are on the island borders, and which linked_edges
		can lead to a triangle that have another triangle.island value.

		<ul>
		<li>There is no need to register all possible exit triangles. Only one per adjacent island is enough.</li>
		<li>Generally it is 4 walkable triangles: 1 top left, 2 bot left and 1 bot right</li>
		</ul>
		*/
		uint32_t[] exit_triangles;

		private void parse(ref ChunkReader wmdata){
			header = wmdata.read!(typeof(header));

			immutable adjLen = wmdata.read!uint32_t;
			adjacent_islands = wmdata.readArray!uint32_t(adjLen).dup;

			immutable adjDistLen = wmdata.read!uint32_t;
			adjacent_islands_dist = wmdata.readArray!float(adjDistLen).dup;

			immutable exitLen = wmdata.read!uint32_t;
			exit_triangles = wmdata.readArray!uint32_t(exitLen).dup;
		}
		private void serialize(ref ChunkWriter uncompData) const {
			uncompData.put(
				header,
				cast(uint32_t)adjacent_islands.length,
				adjacent_islands,
				cast(uint32_t)adjacent_islands_dist.length,
				adjacent_islands_dist,
				cast(uint32_t)exit_triangles.length,
				exit_triangles);
		}

		string dump() const {
			return format!"ISLA header: index: %s, tile: %s, center: %s, triangles_count: %s\n"(header.index, header.tile, header.center.position, header.triangles_count)
			     ~ format!"      adjacent_islands: %s\n"(adjacent_islands)
			     ~ format!"      adjacent_islands_dist: %s\n"(adjacent_islands_dist)
			     ~ format!"      exit_triangles: %s\n"(exit_triangles);
		}
	}

	/// Islands list. See `Island`
	Island[] islands;


	static align(1) struct IslandPathNode {
		static assert(this.sizeof == 8);
		uint16_t next; /// Next island index to go to
		uint16_t _padding;
		float weight; /// Distance to `next` island.
	}
	IslandPathNode[] islands_path_nodes;


	/// Build packet with raw data
	this(in ubyte[] payload){
		auto data = ChunkReader(payload);

		ChunkReader* wmdata;

		auto comp_type = data.read!(char[4]);
		if(comp_type == "COMP"){
			immutable comp_length   = data.read!uint32_t;
			immutable uncomp_length = data.read!uint32_t;

			auto comp_wm = data.readArray(comp_length);

			// zlib deflate
			import std.zlib: uncompress;
			auto walkmeshData = cast(ubyte[])uncompress(comp_wm, uncomp_length);
			assert(walkmeshData.length == uncomp_length, "Length mismatch");

			wmdata = new ChunkReader(walkmeshData);
		}
		else{
			wmdata = new ChunkReader(payload);
		}

		header = wmdata.read!Header;
		assert(wmdata.read_ptr==0x35);
		enforce!TrnParseException(header.owns_data, "ASWM packet does not own any data (`header.owns_data=false`)");

		vertices       = wmdata.readArray!Vertex(header.vertices_count).dup;
		switch(header.aswm_version){
			case 0x69:
				edges = wmdata.readArray!Edge_v69(header.edges_count).map!(a => a.upgrade()).array;
				break;
			case 0x6a: .. case 0x6c:
				edges = wmdata.readArray!Edge(header.edges_count).dup;
				break;
			default: enforce(0, "Unsupported ASWM version " ~ header.aswm_version.format!"0x%02x");
		}
		switch(header.aswm_version){
			case 0x69:
				triangles = wmdata.readArray!Triangle_v69(header.triangles_count).map!(a => a.upgrade()).array;
				break;
			case 0x6a:
				triangles = wmdata.readArray!Triangle_v6a(header.triangles_count).map!(a => a.upgrade()).array;
				break;
			case 0x6b, 0x6c:
				triangles = wmdata.readArray!Triangle(header.triangles_count).dup;
				break;
			default: enforce(0, "Unsupported ASWM version " ~ header.aswm_version.format!"0x%02x");
		}

		tiles_flags       = wmdata.read!(typeof(tiles_flags));
		tiles_width       = wmdata.read!(typeof(tiles_width));
		tiles_grid_height = wmdata.read!(typeof(tiles_grid_height));
		tiles_grid_width  = wmdata.read!(typeof(tiles_grid_width));

		// Tile list
		tiles.length = tiles_grid_height * tiles_grid_width;
		foreach(i, ref tile ; tiles){
			// Path table
			tile.parse(*wmdata, header.aswm_version);
		}

		tiles_border_size = wmdata.read!(typeof(tiles_border_size));

		// Islands list
		islands.length = wmdata.read!uint32_t;
		foreach(ref island ; islands){
			island.parse(*wmdata);
		}

		islands_path_nodes = wmdata.readArray!IslandPathNode(islands.length ^^ 2).dup;

		enforce!TrnParseException(wmdata.read_ptr == wmdata.data.length,
			(wmdata.data.length - wmdata.read_ptr).to!string ~ " bytes were not read at the end of ASWM");

		version(unittest){
			auto serialized = serializeUncompressed();
			assert(serialized.length == wmdata.data.length, "mismatch length "~wmdata.data.length.to!string~" -> "~serialized.length.to!string);
			assert(wmdata.data == serialized, "Could not serialize correctly");
		}
	}


	/**
	Serialize TRN packet data
	*/
	ubyte[] serialize() const {
		auto uncompData = serializeUncompressed();

		import std.zlib: compress;
		const compData = compress(uncompData);

		const compLength = compData.length.to!uint32_t;
		const uncompLength = uncompData.length.to!uint32_t;


		ChunkWriter cw;
		cw.put(cast(char[4])"COMP", compLength, uncompLength, compData);
		return cw.data;
	}

	/**
	Serialize the aswm data without compressing it. Useful for debugging raw data.
	*/
	ubyte[] serializeUncompressed() const {
		//update header values
		Header updatedHeader = header;
		updatedHeader.aswm_version = 0x6c; // Only 0x6c serialization is supported
		updatedHeader.owns_data = true;
		updatedHeader.vertices_count  = vertices.length.to!uint32_t;
		updatedHeader.edges_count = edges.length.to!uint32_t;
		updatedHeader.triangles_count = triangles.length.to!uint32_t;

		//build uncompressed data
		ChunkWriter uncompData;
		uncompData.put(
			updatedHeader,
			vertices,
			edges,
			triangles,
			tiles_flags,
			tiles_width,
			tiles_grid_height,
			tiles_grid_width);

		foreach(ref tile ; tiles){
			tile.serialize(uncompData);
		}

		uncompData.put(
			tiles_border_size,
			cast(uint32_t)islands.length);

		foreach(ref island ; islands){
			island.serialize(uncompData);
		}

		uncompData.put(islands_path_nodes);

		return uncompData.data;
	}

	/**
	Check if the ASWM contains legit data

	Throws: ASWMInvalidValueException containing the error message
	Args:
	strict = false to allow some data inconsistencies that does not cause issues with nwn2
	*/
	void validate(bool strict = false) const {

		immutable vertLen = vertices.length;
		immutable edgeLen = edges.length;
		immutable triLen = triangles.length;
		immutable islLen = islands.length;

		// Vertices
		foreach(vi, v ; vertices){
			enforce!ASWMInvalidValueException(v.position[].all!"!a.isNaN",
				format!"vertices[%d] has an invalid position: %s"(vi, v));
		}

		// Edges
		foreach(iedge, ref edge ; edges){
			foreach(v ; edge.vertices){
				enforce!ASWMInvalidValueException(v < vertLen,
					format!"edges[%d]: Vertex index %d is out of range (0..%d)"(iedge, v, vertLen));
			}
			foreach(t ; edge.triangles){
				enforce!ASWMInvalidValueException(t == uint32_t.max || t < triLen,
					format!"edges[%d]: Triangle index %d is out of range (0..%d)"(iedge, t, triLen));
			}
		}

		// Triangles
		foreach(itri, ref tri ; triangles){
			foreach(v ; tri.vertices){
				enforce!ASWMInvalidValueException(v < vertLen,
					format!"triangles[%d]: Vertex index %s is out of range (0..%d)"(itri, v, vertLen));
			}

			foreach(i ; 0 .. 3){
				immutable lj = tri.linked_edges[i];
				immutable lt = tri.linked_triangles[i];

				enforce!ASWMInvalidValueException(lj < edgeLen,
					format!"triangles[%d].linked_edges[%d]: Edge index %d is out of range (0..%d)"(itri, i, lj, edgeLen));

				enforce!ASWMInvalidValueException(lt == uint32_t.max || lt < triLen,
					format!"triangles[%d].linked_triangles[%d]: Triangle index %d is out of range (0..%d)"(itri, i, lt, triLen));

				enforce!ASWMInvalidValueException(
					(edges[lj].triangles[0] == itri && edges[lj].triangles[1] == lt)
					|| (edges[lj].triangles[0] == lt && edges[lj].triangles[1] == itri),
					format!"triangles[%d].linked_xxx[%d]: linked edge does not match linked triangle"(itri, i));
			}

			if(islLen == 0){
				if(strict)
					enforce!ASWMInvalidValueException(tri.island == uint16_t.max,
						format!"triangles[%d].island: No islands are defined in the ASWM data. The island index %d should be 0xffff"(itri, tri.island));
			}
			else
				enforce!ASWMInvalidValueException(tri.island == uint16_t.max || tri.island < islLen,
					format!"triangles[%d].island: Island index %d is out of range (0..%d)"(itri, tri.island, islLen));
		}

		// Tiles
		enforce!ASWMInvalidValueException(tiles.length == tiles_grid_width * tiles_grid_height,
			format!"Wrong number of tiles: %d instead of %d (tiles_grid_width * tiles_grid_height)"(tiles.length, tiles_grid_width * tiles_grid_height));

		enforce!ASWMInvalidValueException(tiles_width > 0.0,
			"tiles_width: must be > 0");

		foreach(i, ref tile ; tiles){
			try tile.validate(this, cast(uint32_t)i, strict);
			catch(ASWMInvalidValueException e){
				e.msg = format!"tiles[%d]: %s"(i, e.msg);
				throw e;
			}
		}

		uint32_t[] overlapingTri;
		overlapingTri.length = triangles.length;
		overlapingTri[] = uint32_t.max;
		foreach(i, ref tile ; tiles){
			foreach(t ; tile.header.triangles_offset .. tile.header.triangles_offset + tile.header.triangles_count){
				enforce!ASWMInvalidValueException(overlapingTri[t] == uint32_t.max,
					format!"tiles[%d]: Triangle index %d (center=%s) is already owned by tile %d"(i, t, triangles[t].center, overlapingTri[t]));

				overlapingTri[t] = cast(uint32_t)i;
			}
		}

		// Islands
		foreach(isli, ref island ; islands){

			enforce!ASWMInvalidValueException(island.header.index == isli,
				format!"islands[%d].header.index: does not match island index in islands array"(isli));

			enforce!ASWMInvalidValueException(
				island.adjacent_islands.length == island.adjacent_islands_dist.length
				&& island.adjacent_islands.length == island.exit_triangles.length,
				format!"islands[%d]: adjacent_islands/adjacent_islands_dist/exit_triangles lengths must match"(isli));

			foreach(i ; 0 .. island.adjacent_islands.length){
				enforce!ASWMInvalidValueException(island.adjacent_islands[i] < islLen,// Note: Skywing allows uint16_t.max value
					format!"islands[%d].adjacent_islands[%d]: Island index %d is out of range (0..%d)"(isli, i, island.adjacent_islands[i], islLen));
				enforce!ASWMInvalidValueException(island.exit_triangles[i] < triLen,
					format!"islands[%d].exit_triangles[%d]: Triangle index %d is out of range (0..%d)"(isli, i, island.exit_triangles[i], triLen));


				foreach(exitIdx, t ; island.exit_triangles){
					enforce!ASWMInvalidValueException(triangles[t].island == isli,
						format!"islands[%d].exit_triangles[%d]: Triangle index %d is not linked to this island"(isli, exitIdx, t));

					bool found = false;
					foreach(lt ; triangles[t].linked_triangles){
						if(lt != uint32_t.max
						&& triangles[lt].island == island.adjacent_islands[exitIdx]){
							found = true;
							break;
						}
					}
					enforce!ASWMInvalidValueException(found,
						format!"islands[%d].exit_triangles[%d]: Triangle index %d is not adjacent to island %d"(isli, exitIdx, t, island.adjacent_islands[exitIdx]));
				}

			}
		}

		// Island path nodes
		enforce!ASWMInvalidValueException(islands_path_nodes.length == islands.length ^^ 2,
			format!"Wrong number of islands / islands_path_nodes: %d instead of %d"(islands_path_nodes.length, islands.length ^^ 2));

		foreach(i, ipn ; islands_path_nodes){
			enforce!ASWMInvalidValueException(ipn.next == uint16_t.max || ipn.next < islLen,
				format!"islands_path_nodes[%d]: Island index %d is out of range (0..%d)"(i, ipn.next, islLen));
		}
	}

	/**
	Dump trn data as text
	*/
	string dump() const {
		import std.algorithm;
		import std.array: array;

		string ret;

		ret ~= "==== HEADER ====\n";
		ret ~= "aswm_version: " ~ header.aswm_version.to!string ~ "\n";
		ret ~= "name: " ~ header.name.charArrayToString ~ "\n";
		ret ~= "owns_data: " ~ header.owns_data.to!string ~ "\n";
		ret ~= "vertices_count: " ~ header.vertices_count.to!string ~ "\n";
		ret ~= "edges_count: " ~ header.edges_count.to!string ~ "\n";
		ret ~= "triangles_count: " ~ header.triangles_count.to!string ~ "\n";
		ret ~= "unknownB: " ~ header.unknownB.to!string ~ "\n";

		ret ~= "==== VERTICES ====\n";
		ret ~= vertices.map!(a => format!"VERT %s\n"(a.position)).join;

		ret ~= "==== EDGES ====\n";
		ret ~= edges.map!(a => format!"EDGE line: %s, tri: %s\n"(a.vertices, a.triangles)).join;

		ret ~= "==== TRIANGLES ====\n";
		ret ~= triangles.map!(a =>
				  format!"TRI vert: %s, edge: %s, tri: %s\n"(a.vertices, a.linked_edges, a.linked_triangles)
				~ format!"    center: %s, normal: %s, dot_product: %s\n"(a.center, a.normal, a.dot_product)
				~ format!"    island: %s, flags: %s\n"(a.island, a.flags)
			).join;

		ret ~= "==== TILES HEADER ====\n";
		ret ~= "tiles_flags: " ~ tiles_flags.to!string ~ "\n";
		ret ~= "tiles_width: " ~ tiles_width.to!string ~ "\n";
		ret ~= "tiles_grid_height: " ~ tiles_grid_height.to!string ~ "\n";
		ret ~= "tiles_grid_width: " ~ tiles_grid_width.to!string ~ "\n";
		ret ~= "tiles_border_size: " ~ tiles_border_size.to!string ~ "\n";

		ret ~= "==== TILES ====\n";
		ret ~= tiles.map!(a => a.dump()).join;

		ret ~= "==== ISLANDS ====\n";
		ret ~= islands.map!(a => a.dump()).join;

		ret ~= "==== ISLAND PATH NODES ====\n";
		ret ~= islands_path_nodes.map!(a => format!"ISPN next: %s, _padding %s, weight: %s\n"(a.next, a._padding, a.weight)).join;

		return ret;
	}



	// Each entry is one triangle index from every separate island on this tile
	private static struct IslandMeta{
		uint32_t tile;
		uint32_t islandTriangle;
		// This will store all edges that can lead to other tiles
		uint32_t[] edges;
	}

	/**
	Removes triangles from the mesh, and removes unused vertices and edges accordingly.

	Also updates vertex / edge / triangle indices to match new indices.

	Does not updates path tables. You need to run `bake()` to re-generate path tables.

	Params:
	removeFunc = Delegate to check is triangle must be removed.
	*/
	void removeTriangles(bool delegate(in Triangle) removeFunc){
		uint32_t[] vertTransTable, edgeTransTable, triTransTable;
		vertTransTable.length = vertices.length;
		edgeTransTable.length = edges.length;
		triTransTable.length = triangles.length;
		vertTransTable[] = uint32_t.max;
		edgeTransTable[] = uint32_t.max;
		triTransTable[] = uint32_t.max;

		bool[] usedEdges, usedVertices;
		usedVertices.length = vertices.length;
		usedEdges.length = edges.length;
		usedVertices[] = false;
		usedEdges[] = false;

		// Reduce triangle list & flag used edges
		uint32_t newIndex = 0;
		foreach(i, ref triangle ; triangles){
			if(removeFunc(triangle)){

				// Flag used / unused vertices & edges
				foreach(vert ; triangle.vertices){
					usedVertices[vert] = true;
				}
				foreach(edge ; triangle.linked_edges){
					if(edge != uint32_t.max)
						usedEdges[edge] = true;
				}

				// Reduce triangle list in place
				triangles[newIndex] = triangle;
				triTransTable[i] = newIndex++;
			}
			else
				triTransTable[i] = uint32_t.max;
		}
		triangles.length = newIndex;

		// Reduce vertices list
		newIndex = 0;
		foreach(i, used ; usedVertices){
			if(used){
				vertices[newIndex] = vertices[i];
				vertTransTable[i] = newIndex++;
			}
			else
				vertTransTable[i] = uint32_t.max;
		}
		vertices.length = newIndex;

		// Reduce edges list
		newIndex = 0;
		foreach(i, used ; usedEdges){
			if(used){
				edges[newIndex] = edges[i];
				edgeTransTable[i] = newIndex++;
			}
			else
				edgeTransTable[i] = uint32_t.max;
		}
		edges.length = newIndex;

		translateIndices(triTransTable, edgeTransTable, vertTransTable);
	}

	/**
	Translate triangle / edge / vertex indices stored in mesh data.

	Each argument is a table of the length of the existing list where:
	<ul>
	<li>The index is the index of the current triangle</li>
	<li>The value is the index of the translated triangle</li>
	</ul>
	If the argument is an empty array, no translation is done. Does NOT update path tables & islands data.
	*/
	void translateIndices(uint32_t[] triTransTable, uint32_t[] edgeTransTable, uint32_t[] vertTransTable){
		immutable ttrans = triTransTable.length > 0;
		immutable jtrans = edgeTransTable.length > 0;
		immutable vtrans = vertTransTable.length > 0;

		// Adjust indices in edges data
		foreach(ref edge ; edges){
			if(vtrans){
				foreach(ref vert ; edge.vertices){
					vert = vertTransTable[vert];
					assert(vert != uint32_t.max && vert < vertices.length, "Invalid vertex index");
				}
			}
			if(ttrans){
				foreach(ref tri ; edge.triangles){
					if(tri != uint32_t.max){
						tri = triTransTable[tri];
						assert(tri == uint32_t.max || tri < triangles.length, "Invalid triangle index");
					}
				}

			}
			// Pack triangle indices (may be overkill)
			if(edge.triangles[0] == uint32_t.max && edge.triangles[1] != uint32_t.max){
				edge.triangles[0] = edge.triangles[1];
				edge.triangles[1] = uint32_t.max;
			}
		}

		// Adjust indices in triangles data
		foreach(ref triangle ; triangles){
			if(vtrans){
				foreach(ref vert ; triangle.vertices){
					vert = vertTransTable[vert];
					assert(vert != uint32_t.max && vert < vertices.length, "Invalid vertex index");
				}
			}
			if(jtrans){
				foreach(ref edge ; triangle.linked_edges){
					edge = edgeTransTable[edge];//All triangles should have 3 edges
					assert(edge < edges.length, "Invalid edge index");
				}
			}
			if(ttrans){
				foreach(ref tri ; triangle.linked_triangles){
					if(tri != uint32_t.max){
						tri = triTransTable[tri];
					}
				}
			}
		}

	}

	/// Reorder triangles and prepare tile triangles associations
	private
	void splitTiles(){
		uint32_t[] triTransTable;
		triTransTable.length = triangles.length;
		triTransTable[] = uint32_t.max;


		Triangle[] newTriangles;
		newTriangles.length = triangles.length;
		uint32_t newTrianglesPtr = 0;

		foreach(y ; 0 .. tiles_grid_height){
			foreach(x ; 0 .. tiles_grid_width){
				auto tileAABB = box2f(
					vec2f(x * tiles_width,       y * tiles_width),
					vec2f((x + 1) * tiles_width, (y + 1) * tiles_width));

				auto tile = &tiles[y * tiles_grid_width + x];
				tile.header.triangles_offset = newTrianglesPtr;

				foreach(i, ref tri ; triangles){
					if(tileAABB.contains(vec2f(tri.center))){
						newTriangles[newTrianglesPtr] = tri;
						triTransTable[i] = newTrianglesPtr;
						newTrianglesPtr++;
					}
				}
				tile.header.triangles_count = newTrianglesPtr - tile.header.triangles_offset;
			}
		}

		triangles = newTriangles[0 .. newTrianglesPtr];

		translateIndices(triTransTable, [], []);
	}

	/**
	Bake the existing walkmesh by re-creating tiles, islands, path tables, ...

	Does not modify the current walkmesh like what you would expect with
	placeable walkmesh / walkmesh cutters.

	Params:
	removeBorders = true to remove unwalkable map borders from the walkmesh.
	*/
	void bake(bool removeBorders = true){
		// Reset island associations
		triangles.each!((ref a) => a.island = 0xffff);

		// Remove border triangles
		if(removeBorders){
			auto terrainAABB = box2f(
				vec2f(tiles_border_size * tiles_width, tiles_border_size * tiles_width),
				vec2f((tiles_grid_width - tiles_border_size) * tiles_width, (tiles_grid_height - tiles_border_size) * tiles_width));

			removeTriangles(a => terrainAABB.contains(vec2f(a.center)));
		}

		// Reorder triangles to have consecutive triangles for each tile
		splitTiles();

		IslandMeta[] islandsMeta;
		islandsMeta.reserve(tiles.length * 2);

		// Bake tiles
		foreach(i ; 0 .. tiles.length){
			//removeBorders
			islandsMeta ~= bakeTile(i.to!uint32_t);
		}

		// islandTileID looks random-ish in TRX files. Here we generate by
		// calculating a 32bit CRC with islandsMeta data, so bake() result is
		// reproducible
		import std.digest.crc: crc32Of;
		auto islandTileID = *cast(uint32_t*)crc32Of(islandsMeta).ptr;

		islands.length = islandsMeta.length;
		foreach(i, ref island ; islands){
			// Set island index
			island.header.index = i.to!uint32_t;

			// Set island associated tile
			//island.header.tile = islandsMeta[i].tile;
			island.header.tile = islandTileID;

			auto tile = &tiles[islandsMeta[i].tile];
			auto tileTriangleOffset = tile.header.triangles_offset;
			auto firstLTri = islandsMeta[i].islandTriangle - tileTriangleOffset;
			auto tileNTLLen = tile.path_table.node_to_local.length;
			auto nodeIndex = tile.path_table.local_to_node[firstLTri];

			assert(nodeIndex != 0xff, "BakeTile returned a non walkable islandTriangle");

			//writeln("len=", tile.path_table.nodes.length, " [", tileNTLLen * nodeIndex, " .. ", tileNTLLen * (nodeIndex + 1), "], ntllen=", tileNTLLen);
			auto nodes = tile.path_table.nodes[tileNTLLen * nodeIndex .. tileNTLLen * (nodeIndex + 1)];

			// Retrieve island triangle list
			uint32_t[] islandTriangles;
			islandTriangles.reserve(nodes.length);

			islandTriangles ~= islandsMeta[i].islandTriangle;
			foreach(j, node ; nodes){
				// TODO: o(n^^2)
				if(node != 0xff)
					islandTriangles ~= (tile.path_table.local_to_node.countUntil(j) + tileTriangleOffset).to!uint32_t;
			}

			// Set island triangle count
			island.header.triangles_count = islandTriangles.length.to!uint32_t;

			// Set island center (calculated by avg all triangle centers)
			island.header.center.position = [0,0,0];
			foreach(t ; islandTriangles)
				island.header.center.position[0 .. 2] += triangles[t].center[];
			island.header.center.position[] /= cast(double)islandTriangles.length;

			// Set triangle associated island index
			foreach(t ; islandTriangles)
				triangles[t].island = i.to!uint16_t;
		}

		// Set island connections
		foreach(i, ref island ; islands){

			island.adjacent_islands.length = 0;
			island.adjacent_islands_dist.length = 0;
			island.exit_triangles.length = 0;

			foreach(edge ; islandsMeta[i].edges){

				uint32_t exitTriangle = uint32_t.max;
				uint32_t exitIsland = uint32_t.max;

				foreach(t ; edges[edge].triangles){
					immutable islandIdx = triangles[t].island;
					if(islandIdx == i)
						exitTriangle = t;
					else
						exitIsland = islandIdx;
				}

				if(exitTriangle != uint32_t.max && exitIsland != uint32_t.max
				&& island.adjacent_islands.find(exitIsland).empty){
					island.adjacent_islands ~= exitIsland;
					island.exit_triangles ~= exitTriangle;

					// Calculate island distance
					import std.math: sqrt;
					auto dist = islands[exitIsland].header.center.position.dup;
					dist[] -= island.header.center.position[];
					island.adjacent_islands_dist ~= sqrt(dist[0] ^^ 2 + dist[1] ^^ 2);
				}

			}
		}

		// Rebuild island path tables
		islands_path_nodes.length = islands.length ^^ 2;
		islands_path_nodes[] = IslandPathNode(uint16_t.max, 0, 0.0);


		foreach(fromIslandIdx, ref fromIsland ; islands){

			bool[] visitedIslands;
			visitedIslands.length = islands.length;
			visitedIslands[] = false;


			static struct NextToExplore{
				uint16_t[] list;
				uint16_t target = uint16_t.max;
				float distance = 0.0;
			}
			auto getIslandPathNode(uint32_t from, uint32_t to){
				return &islands_path_nodes[from * islands.length + to];
			}

			NextToExplore[] explore(uint16_t islandIdx, uint16_t targetIsland = uint16_t.max, float distance = 0.0){
				NextToExplore[] ret;
				if(targetIsland != uint16_t.max)
					ret ~= NextToExplore([], targetIsland, distance);


				foreach(j, linkedIslIdx ; islands[islandIdx].adjacent_islands){

					if(linkedIslIdx == fromIslandIdx)
						continue;// We must not visit initial island (node value must stay as 0xff)

					auto linkedIsl = &islands[linkedIslIdx];

					auto node = getIslandPathNode(cast(uint32_t)fromIslandIdx, linkedIslIdx);
					if(node.next == uint16_t.max){
						// This is the first time we visit the island from this fromTriIdx

						if(targetIsland == uint16_t.max){
							ret ~= NextToExplore([], linkedIslIdx.to!uint16_t, islands[islandIdx].adjacent_islands_dist[j]);
						}

						ret[$-1].list ~= linkedIslIdx.to!uint16_t;

						node.next = ret[$-1].target;
						node.weight = ret[$-1].distance;
					}
				}
				return ret;
			}

			NextToExplore[] nextToExplore = [ NextToExplore([fromIslandIdx.to!uint16_t]) ];
			NextToExplore[] newNextToExplore;
			while(nextToExplore.length > 0 && nextToExplore.map!(a => a.list.length).sum > 0){
				foreach(ref nte ; nextToExplore){
					foreach(t ; nte.list){
						newNextToExplore ~= explore(t, nte.target, nte.distance);
					}
				}
				nextToExplore = newNextToExplore;
				newNextToExplore.length = 0;
			}

		}

		debug validate();
	}

	/// Bake tile path table
	private IslandMeta[] bakeTile(uint32_t tileIndex){
		//writeln("bakeTile: ", tileIndex);

		auto tile = &tiles[tileIndex];
		uint32_t tileX = tileIndex % tiles_grid_width;
		uint32_t tileY = tileIndex / tiles_grid_width;

		// Get tile bounding box
		auto tileAABB = box2f(
			vec2f(tileX * tiles_width, tileY * tiles_width),
			vec2f((tileX + 1) * tiles_width, (tileY + 1) * tiles_width));

		// Build tile triangle list
		immutable trianglesOffset = tile.header.triangles_offset;
		uint32_t[] tileTriangles;
		tileTriangles.length = tile.header.triangles_count;
		foreach(i, ref t ; tileTriangles)
			t = (i + trianglesOffset).to!uint32_t;

		// Recalculate edge & vert count
		tile.header.edges_count = triangles[trianglesOffset .. trianglesOffset + tile.header.triangles_count]
			.map!((ref a) => a.linked_edges[])
			.join
			.filter!(a => a != a.max)
			.array
			.sort
			.uniq
			.array.length.to!uint32_t;
		tile.header.vertices_count = triangles[trianglesOffset .. trianglesOffset + tile.header.triangles_count]
			.map!((ref a) => a.vertices[])
			.join
			.filter!(a => a != a.max)
			.array
			.sort
			.uniq
			.array.length.to!uint32_t;


		// Find walkable triangles to deduce NTL length & LTN content
		const walkableTriangles = tileTriangles.filter!(a => triangles[a].flags & Triangle.Flags.walkable).array;
		immutable walkableTrianglesLen = walkableTriangles.length.to!uint32_t;

		// node_to_local indices are stored on 7 bits
		enforce(walkableTrianglesLen < 0b0111_1111, "Too many walkable triangles on a single tile");

		// Fill NTL with walkable triangles local indices
		tile.path_table.node_to_local = walkableTriangles.dup;
		tile.path_table.node_to_local[] -= trianglesOffset;
		ubyte getNtlIndex(uint32_t destTriangle){
			destTriangle -= trianglesOffset;
			// insert destTriangle inside ntl and return its index
			foreach(i, t ; tile.path_table.node_to_local){
				if(t == destTriangle)
					return i.to!ubyte;
			}
			assert(0, "Triangle local idx="~destTriangle.to!string~" not found in NTL array "~tile.path_table.node_to_local.to!string);
		}

		// Set LTN content: 0xff if the triangle is unwalkable, otherwise an
		// index in walkableTriangles
		tile.path_table.local_to_node.length = tile.header.triangles_count;

		tile.path_table.local_to_node[] = 0xff;
		foreach(i, triIdx ; walkableTriangles)
			tile.path_table.local_to_node[triIdx - trianglesOffset] = i.to!ubyte;

		// Resize nodes table
		tile.path_table.nodes.length = (walkableTrianglesLen * walkableTrianglesLen).to!uint32_t;
		tile.path_table.nodes[] = 0xff;// 0xff means inaccessible.


		ubyte* getNode(uint32_t fromGIdx, uint32_t toGIdx) {
			return &tile.path_table.nodes[
				tile.path_table.local_to_node[fromGIdx - trianglesOffset] * walkableTrianglesLen
				+ tile.path_table.local_to_node[toGIdx - trianglesOffset]
			];
		}


		// Visited triangles. Not used for pathfinding, but for island detection.
		bool[] visitedTriangles;
		visitedTriangles.length = tile.path_table.local_to_node.length;
		visitedTriangles[] = false;


		IslandMeta[] islandsMeta;
		bool islandRegistration = false;


		// Calculate pathfinding
		foreach(i, fromTriIdx ; walkableTriangles){

			// If the triangle has not been visited before, we add a new
			// island All triangles accessible from this one will be marked as
			// visited, so we don't add more than once the same island
			if(visitedTriangles[fromTriIdx - trianglesOffset] == false){
				islandsMeta ~= IslandMeta(tileIndex, fromTriIdx, []);
				islandRegistration = true;
			}
			else
				islandRegistration = false;

			float[] costTable;
			costTable.length = tile.path_table.local_to_node.length;
			costTable[] = float.infinity;

			static struct NextToExplore{
				Tuple!(uint32_t, float)[] list;
				ubyte ntlTarget = ubyte.max;
			}

			NextToExplore[] explore(uint32_t currTriIdx, float currCost, ubyte ntlTarget = ubyte.max){
				//TODO: currently the fastest route is the route that cross
				//the minimum number of triangles, which isn't always true. We
				//need to take the distance between triangles into account

				NextToExplore[] ret;
				if(ntlTarget != ubyte.max)
					ret ~= NextToExplore([], ntlTarget);

				foreach(j, linkedTriIdx ; triangles[currTriIdx].linked_triangles){
					if(linkedTriIdx == uint32_t.max)
						continue;// there is no linked triangle

					if(fromTriIdx == linkedTriIdx)
						continue;// We must not visit initial triangle (node value must stay as 0xff)

					auto linkedTri = &triangles[linkedTriIdx];

					if(!(linkedTri.flags & linkedTri.Flags.walkable))
						continue;// non walkable triangle

					if(tileAABB.contains(vec2f(linkedTri.center))){
						// linkedTri is inside the tile

						// Mark the triangle as visited (only for island detection)
						visitedTriangles[linkedTriIdx - trianglesOffset] = true;

						float cost = currCost + vec2f(triangles[currTriIdx].center).distanceTo(vec2f(linkedTri.center));

						if(cost < costTable[linkedTriIdx - trianglesOffset]){
							costTable[linkedTriIdx - trianglesOffset] = cost;

							auto node = getNode(fromTriIdx, linkedTriIdx);
							if(ntlTarget == ubyte.max){
								ret ~= NextToExplore([], getNtlIndex(linkedTriIdx));
							}

							ret[$-1].list ~= Tuple!(uint32_t, float)(linkedTriIdx, cost);

							assert(ret[$-1].ntlTarget < 0b0111_1111);
							*node = ret[$-1].ntlTarget;// TODO: do VISIBLE / LOS calculation
						}

					}
					else{
						// linkedTri is outside the tile
						if(islandRegistration){
							immutable edgeIdx = triangles[currTriIdx].linked_edges[j];
							assert(edges[edgeIdx].triangles[0] == currTriIdx && edges[edgeIdx].triangles[1] == linkedTriIdx
								|| edges[edgeIdx].triangles[1] == currTriIdx && edges[edgeIdx].triangles[0] == linkedTriIdx,
								"Incoherent edge "~edgeIdx.to!string~": "~edges[edgeIdx].to!string);
							islandsMeta[$-1].edges ~= edgeIdx;
						}
					}
				}
				return ret;
			}

			NextToExplore[] nextToExplore = [ NextToExplore([Tuple!(uint32_t,float)(fromTriIdx, 0)]) ];
			NextToExplore[] newNextToExplore;
			while(nextToExplore.length > 0 && nextToExplore.map!(a => a.list.length).sum > 0){
				foreach(ref nte ; nextToExplore){
					foreach(t ; nte.list){
						newNextToExplore ~= explore(t[0], t[1], nte.ntlTarget);
					}
				}
				nextToExplore = newNextToExplore;
				newNextToExplore.length = 0;
			}
		}

		//if(walkableTrianglesLen > 0)
		//	writeln("Tile ", tileIndex, ": ", walkableTrianglesLen, " walkable triangles in ", islandsMeta.length, " islands");
		return islandsMeta;
	}

	/// Set the footstep sound flags for each triangle of the walkmesh
	/// Params:
	/// trrnPackets = TRN packet list containing the needed `TrnNWN2MegatilePayload` packets
	/// textureFlags = Associative array listing all textures and their respective footstep sounds
	void setFootstepSounds(in TrnPacket[] trrnPackets, in Triangle.Flags[string] textureFlags){
		import nwn.dds;

		// Prepare megatile info for quick access
		static struct Megatile {
			box2f aabb;
			string[6] textures;
			Dds[2] dds;
		}
		Megatile[] megatiles;
		foreach(ref packet ; trrnPackets){
			if(packet.type == TrnPacketType.NWN2_TRRN){
				with(packet.as!(TrnPacketType.NWN2_TRRN)){
					Megatile megatile;

					auto min = vec2f(float.infinity, float.infinity);
					auto max = vec2f(-float.infinity, -float.infinity);
					foreach(ref v ; vertices){
						if(v.position[0] < min.x || v.position[1] < min.y) min = vec2f(v.position[0..2]);
						if(v.position[0] > max.x || v.position[1] > max.y) max = vec2f(v.position[0..2]);
					}
					megatile.aabb = box2f(min, max);

					foreach(i ; 0 .. 6)
						megatile.textures[i] = textures[i].name.ptr.fromStringz.idup;

					megatile.dds[0] = Dds(dds_a);
					megatile.dds[1] = Dds(dds_b);

					megatiles ~= megatile;
				}
			}
		}

		foreach(i, ref t ; triangles){
			bool found = false;
			// TODO: sort these megatiles by row so we can find the megatile for any triangle with o(1)
			foreach(ref mt ; megatiles){
				if(mt.aabb.contains(cast(vec2f)t.center)){
					found = true;

					auto pos = vec2i(((t.center - mt.aabb.min) * mt.dds[0].header.width / mt.aabb.size.magnitude)[].to!(int[]));
					auto p0 = mt.dds[0].getPixel(pos.x, pos.y);
					auto p1 = mt.dds[1].getPixel(pos.x, pos.y);

					ubyte maxTextureIdx = ubyte.max;
					int maxTextureIntensity = -1;
					foreach(textureIdx, intensity ; p0[0 .. 4] ~ p1[0 .. 2]){
						if(mt.textures[textureIdx].length > 0 && intensity > maxTextureIntensity){
							maxTextureIdx = cast(ubyte)textureIdx;
							maxTextureIntensity = intensity;
						}
					}
					assert(maxTextureIdx != ubyte.max, "No texture found");

					if(auto flag = mt.textures[maxTextureIdx] in textureFlags){
						t.flags &= t.flags.max ^ Triangle.Flags.soundstepFlags;
						t.flags |= *flag;
					}
					else
						assert(0, "Texture '"~mt.textures[maxTextureIdx]~"' not in texture/flag list");

					break;
				}
			}
			enforce(found, "No megatile found for triangle "~i.to!string);
		}
	}

	/// ditto
	/// Params:
	/// trrnPackets = TRN packet list containing the needed `TrnNWN2MegatilePayload` packets
	/// terrainmaterials = terrainmaterials.2da that lists all textures and their respective footstep sounds
	void setFootstepSounds(in TrnPacket[] trrnPackets, in TwoDA terrainmaterials){
		// Find soundstep flags for each
		Triangle.Flags[string] textureFlags;
		immutable materialColIdx = terrainmaterials.columnIndex("Material");
		foreach(i ; 0 .. terrainmaterials.rows){

			Triangle.Flags flag;
			switch(terrainmaterials.get("Material", i)){
				case "Dirt":    flag = Triangle.Flags.dirt; break;
				case "Grass":   flag = Triangle.Flags.grass; break;
				case "Rock",
				     "Stone":   flag = Triangle.Flags.stone; break;
				case "Wood":    flag = Triangle.Flags.wood; break;
				case "Carpet":  flag = Triangle.Flags.carpet; break;
				case "Metal":   flag = Triangle.Flags.metal; break;
				case "Swamp":   flag = Triangle.Flags.swamp; break;
				case "Mud":     flag = Triangle.Flags.mud; break;
				case "Leaves":  flag = Triangle.Flags.leaves; break;
				case "Water":   flag = Triangle.Flags.water; break;
				case "Puddles": flag = Triangle.Flags.puddles; break;
				case null:      continue;
				default: assert(0, "Unknown terrain material type '"~terrainmaterials.get("Material", i)~"' in "~terrainmaterials.fileName);
			}
			textureFlags[terrainmaterials.get("Terrain", i)] = flag;
		}

		setFootstepSounds(trrnPackets, textureFlags);
	}

	/**
	Calculate the fastest route between two islands. The area need to be baked, as it uses existing path tables.
	*/
	uint16_t[] findIslandsPath(in uint16_t fromIslandIndex, in uint16_t toIslandIndex) const {
		uint16_t from = fromIslandIndex;
		int iSec = 0;
		uint16_t[] ret;
		while(fromIslandIndex != toIslandIndex && iSec++ < 1000){
			auto node = &islands_path_nodes[from * islands.length + toIslandIndex];
			if(node.next == uint16_t.max)
				return ret;

			from = node.next;
			ret ~= from;
		}
		assert(iSec < 1000, "Islands precalculated paths lead to a loop (from="~fromIslandIndex.to!string~", to="~toIslandIndex.to!string~")");
		return ret;
	}

	/**
	Set 3d mesh geometry
	*/
	void setGenericMesh(in GenericMesh mesh){
		// Copy vertices
		vertices.length = mesh.vertices.length;
		foreach(i, ref v ; vertices)
			v.position = mesh.vertices[i].v;

		// Copy triangles
		triangles.length = mesh.triangles.length;
		foreach(i, ref t ; triangles){
			t.vertices = mesh.triangles[i].vertices.dup[0 .. 3];

			t.linked_edges[] = uint32_t.max;
			t.linked_triangles[] = uint32_t.max;

			t.center = vertices[t.vertices[0]].position[0 .. 2];
			t.center[] += vertices[t.vertices[1]].position[0 .. 2];
			t.center[] += vertices[t.vertices[2]].position[0 .. 2];
			t.center[] /= 3.0;

			t.normal = (mesh.vertices[t.vertices[1]] - mesh.vertices[t.vertices[0]])
				.cross(mesh.vertices[t.vertices[2]] - mesh.vertices[t.vertices[0]]).normalized[0..3];

			t.dot_product = -dot(vec3f(t.normal), mesh.vertices[t.vertices[0]]);

			t.island = uint16_t.max;

			t.flags |= t.Flags.walkable;
			if(isTriangleClockwise(t.vertices[].map!(a => vec2f(vertices[a].position[0 .. 2])).array[0 .. 3]))
				t.flags |= t.Flags.clockwise;
			else
				t.flags &= t.flags.max ^ t.Flags.clockwise;
		}

		// Rebuild edge list
		buildEdges();
	}

	/**
	Converts terrain mesh data to a more generic format.

	Params:
	triangleFlags = Triangle flags to include in the generic mesh.
	Set to `uint16_t.max` to include all triangles.
	*/
	GenericMesh toGenericMesh(uint16_t triangleFlags = Triangle.Flags.walkable) const {
		GenericMesh ret;
		ret.vertices.length = vertices.length;
		ret.triangles.length = triangles.length;

		foreach(i, ref v ; vertices){
			ret.vertices[i] = vec3f(v.position);
		}

		size_t ptr = 0;
		foreach(i, ref t ; triangles){
			if(triangleFlags == uint16_t.max || t.flags & triangleFlags){
				debug foreach(j, v ; t.vertices)
					assert(v < ret.vertices.length, format!"Vertex %d (index=%d) of triangle %d is out of range. Please check mesh with Validate() before conversion."(j, v, i));
				ret.triangles[ptr++] = GenericMesh.Triangle(t.vertices);
			}
		}
		ret.triangles.length = ptr;
		return ret;
	}

	/**
	Rebuilds edge data by going through every triangle / vertices

	Warning: NWN2 official baking tool often produces duplicated triangles and
	edges around placeable walkmeshes.
	*/
	void buildEdges(){
		uint32_t[uint32_t[2]] edgeMap;
		uint32_t findEdge(uint32_t[2] vertices){
			if(auto j = vertices in edgeMap)
				return *j;
			return uint32_t.max;
		}

		edges.length = 0;

		foreach(i, ref t ; triangles){
			// Create edges as needed
			foreach(j ; 0 .. 3){
				auto vrt = [t.vertices[j], t.vertices[(j+1) % 3]].sort.array;
				auto edgeIdx = findEdge(vrt[0 .. 2]);

				if(edgeIdx == uint32_t.max){
					// Add new edge
					edgeMap[vrt[0 .. 2]] = edges.length.to!uint32_t;
					edges ~= Edge(vrt[0 .. 2], [i.to!uint32_t, uint32_t.max]);
				}
				else{
					// Add triangle to existing edge
					enforce(edges[edgeIdx].triangles[1] == uint32_t.max,
						"Edge "~edgeIdx.to!string~" = "~edges[edgeIdx].to!string~" cannot be linked to more than 2 triangles (cannot add triangle "~i.to!string~")");
					edges[edgeIdx].triangles[1] = i.to!uint32_t;
				}
			}
		}

		// update triangles[].linked_edge & triangles[].linked_triangles
		foreach(edgeIdx, ref edge ; edges){
			assert(edge.triangles[0] != uint32_t.max);

			foreach(j, tIdx ; edge.triangles){
				if(tIdx == uint32_t.max)
					continue;

				size_t slot;
				for(slot = 0 ; slot < 3 ; slot++)
					if(triangles[tIdx].linked_edges[slot] == uint32_t.max)
						break;
				assert(slot < 3, "Triangle "~tIdx.to!string~" is already linked to 3 triangles");

				triangles[tIdx].linked_edges[slot] = edgeIdx.to!uint32_t;
				triangles[tIdx].linked_triangles[slot] = edge.triangles[(j + 1) % 2];
			}
		}

	}
}

unittest {
	auto epportesTrx = cast(ubyte[])import("eauprofonde-portes.trx");

	auto trn = new Trn(epportesTrx);
	auto serialized = trn.serialize();
	assert(epportesTrx.length == serialized.length && epportesTrx == serialized);

	auto terrainmaterials = new TwoDA(cast(ubyte[])import("terrainmaterials.2da"));

	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		aswm.validate();
		aswm.bake();

		assertThrown!Error(aswm.tiles[666].findPath(0, 1));// Triangles outside of the tile
		assert(aswm.tiles[666].findPath(15421, 15417).length == 4);// on the same island
		assert(aswm.tiles[666].findPath(15452, 15470).length == 7);// on the same island
		assert(aswm.tiles[778].findPath(20263, 20278).length == 0);// across two islands

		assert(aswm.findIslandsPath(10, 12).length == 2);
		assert(aswm.findIslandsPath(0, (aswm.islands.length - 1).to!uint16_t).length == 49);

		aswm.setFootstepSounds(trn.packets, terrainmaterials);
		aswm.removeTriangles((in t) => (t.flags & t.Flags.walkable) == 0);

		aswm.bake();
		aswm.validate();
	}


	trn = new Trn(cast(ubyte[])import("IslandsTest.trn"));
	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		aswm.validate();

		aswm.bake();
		aswm.validate();

		assert(aswm.triangles.length == 1152);
		assert(aswm.edges.length == 1776);

		auto walkableTrianglesLength = aswm.triangles.count!(a => (a.flags & a.Flags.walkable) > 0);

		auto mesh = aswm.toGenericMesh;

		// Shuffle mesh
		mesh.shuffle();
		aswm.setGenericMesh(mesh);
		aswm.bake();

		aswm.validate();

		// Values taken from trx file baked with the toolset
		assert(aswm.triangles.length == walkableTrianglesLength);
		assert(aswm.islands.length == 25);
	}
}

