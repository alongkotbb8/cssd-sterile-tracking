import { Body, Controller, Delete, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { UserRole } from '@prisma/client';
import { IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';
import { MasterDataService } from './master-data.service';
import { CreateSetTemplateDto } from './dto/create-template.dto';

class CreateTagDto {
  @IsString() @MinLength(1) @MaxLength(50) name: string;
  @IsOptional() @Matches(/^#[0-9a-fA-F]{6}$/) colorHex?: string;
}

@ApiTags('master-data')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('master-data')
export class MasterDataController {
  constructor(private svc: MasterDataService) {}

  @Get('templates') getTemplates() { return this.svc.getTemplates(); }
  @Get('sterilizers') getSterilizers() { return this.svc.getSterilizers(); }

  @Post('templates')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  createTemplate(@Body() dto: CreateSetTemplateDto, @Req() req: any) {
    return this.svc.createTemplate(dto, req.user.id);
  }

  // ── Tags (จัดกลุ่ม/ค้นหาห่อ) ──
  @Get('tags')
  getTags() { return this.svc.getTags(); }

  @Post('tags')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  createTag(@Body() dto: CreateTagDto, @Req() req: any) {
    return this.svc.createTag(dto.name, dto.colorHex, req.user.id);
  }

  @Delete('tags/:id')
  @Roles(UserRole.SUPERVISOR, UserRole.ADMIN)
  deleteTag(@Param('id') id: string, @Req() req: any) {
    return this.svc.deleteTag(id, req.user.id);
  }
}
